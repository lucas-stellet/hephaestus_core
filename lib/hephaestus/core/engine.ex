defmodule Hephaestus.Core.Engine do
  @moduledoc """
  Pure functional workflow engine for the callback-based v2 API.
  """

  alias Hephaestus.Core.{Context, Instance}

  @spec advance(Instance.t()) :: {:ok, Instance.t()} | {:error, term()}
  def advance(%Instance{} = instance) do
    instance = ensure_started(instance)

    cond do
      instance.status == :waiting ->
        {:ok, instance}

      MapSet.size(instance.active_steps) > 0 ->
        {:ok, instance}

      true ->
        {:ok, check_completion(instance)}
    end
  end

  @spec execute_step(Instance.t(), module()) ::
          {:ok, atom()} | {:ok, atom(), map()} | {:async} | {:error, term()}
  def execute_step(%Instance{} = instance, step_module) when is_atom(step_module) do
    ensure_module_loaded(step_module)

    unless function_exported?(step_module, :execute, 3) do
      raise "#{inspect(step_module)} must implement execute/3"
    end

    config = Map.get(instance.step_configs, step_module)
    step_module.execute(instance, config, instance.context)
  end

  @spec complete_step(Instance.t(), module(), atom(), map()) :: Instance.t()
  def complete_step(%Instance{} = instance, step_module, _event, context_updates)
      when is_atom(step_module) and is_map(context_updates) do
    context_key = module_to_context_key(step_module)

    %{
      instance
      | active_steps: MapSet.delete(instance.active_steps, step_module),
        completed_steps: MapSet.put(instance.completed_steps, step_module),
        context: Context.put_step_result(instance.context, context_key, context_updates),
        step_configs: Map.delete(instance.step_configs, step_module)
    }
  end

  @spec resume_step(Instance.t(), module(), atom()) :: Instance.t()
  def resume_step(%Instance{status: :waiting} = instance, step_module, event)
      when is_atom(step_module) and is_atom(event) do
    instance
    |> complete_step(step_module, event, %{})
    |> activate_transitions(step_module, event)
    |> Map.put(:status, :running)
    |> Map.put(:current_step, nil)
  end

  def resume_step(%Instance{} = instance, _step_module, _event), do: instance

  defp ensure_started(%Instance{status: :pending} = instance) do
    start = instance.workflow.start()
    {module, config} = normalize_target(start)

    %{
      instance
      | status: :running,
        current_step: module,
        active_steps: MapSet.put(instance.active_steps, module),
        step_configs: maybe_put_config(instance.step_configs, module, config)
    }
  end

  defp ensure_started(%Instance{} = instance), do: instance

  @spec check_completion(Instance.t()) :: Instance.t()
  def check_completion(%Instance{active_steps: active_steps} = instance) do
    if MapSet.size(active_steps) == 0 and instance.status != :waiting do
      %{instance | status: :completed, current_step: nil}
    else
      instance
    end
  end

  @spec activate_transitions(Instance.t(), module(), atom()) :: Instance.t()
  def activate_transitions(%Instance{} = instance, from_module, event)
      when is_atom(from_module) and is_atom(event) do
    case resolve_transit(instance.workflow, from_module, event, instance) do
      nil ->
        instance

      target when is_atom(target) ->
        maybe_activate_step(instance, target, nil)

      {target, config} ->
        maybe_activate_step(instance, target, config)

      targets when is_list(targets) ->
        Enum.reduce(targets, instance, fn
          {target, config}, acc -> maybe_activate_step(acc, target, config)
          target, acc -> maybe_activate_step(acc, target, nil)
        end)
    end
  end

  defp resolve_transit(workflow, from_module, event, %Instance{} = instance) do
    with nil <- maybe_resolve_transit3(workflow, from_module, event, instance) do
      maybe_resolve_transit2(workflow, from_module, event)
    end
  end

  defp maybe_resolve_transit3(workflow, from_module, event, %Instance{} = instance) do
    ensure_module_loaded(workflow)

    if function_exported?(workflow, :transit, 3) do
      try do
        workflow.transit(from_module, event, instance.context)
      rescue
        error in FunctionClauseError ->
          if transit_clause_miss?(error, workflow, :transit, 3) do
            nil
          else
            reraise(error, __STACKTRACE__)
          end
      end
    end
  end

  defp maybe_resolve_transit2(workflow, from_module, event) do
    ensure_module_loaded(workflow)

    if function_exported?(workflow, :transit, 2) do
      try do
        workflow.transit(from_module, event)
      rescue
        error in FunctionClauseError ->
          if transit_clause_miss?(error, workflow, :transit, 2) do
            nil
          else
            reraise(error, __STACKTRACE__)
          end
      end
    end
  end

  defp transit_clause_miss?(%FunctionClauseError{module: module, function: function, arity: arity}, module, function, arity),
    do: true

  defp transit_clause_miss?(%FunctionClauseError{}, _module, _function, _arity), do: false

  defp maybe_activate_step(%Instance{} = instance, step_module, config) when is_atom(step_module) do
    predecessors = instance.workflow.__predecessors__(step_module)

    if MapSet.subset?(predecessors, instance.completed_steps) do
      %{
        instance
        | active_steps: MapSet.put(instance.active_steps, step_module),
          step_configs: maybe_put_config(instance.step_configs, step_module, config)
      }
    else
      instance
    end
  end

  defp normalize_target(module) when is_atom(module), do: {module, nil}
  defp normalize_target({module, config}) when is_atom(module), do: {module, config}

  defp maybe_put_config(step_configs, _module, nil), do: step_configs
  defp maybe_put_config(step_configs, module, config), do: Map.put(step_configs, module, config)

  defp module_to_context_key(module) do
    ensure_module_loaded(module)

    if function_exported?(module, :step_key, 0) do
      module.step_key()
    else
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()
    end
  end

  defp ensure_module_loaded(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _module} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
