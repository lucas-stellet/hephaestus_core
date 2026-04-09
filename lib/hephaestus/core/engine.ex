defmodule Hephaestus.Core.Engine do
  @moduledoc """
  Pure functional workflow engine for the callback-based v2 API.
  """

  alias Hephaestus.Core.{Context, Instance}

  @doc """
  Advances a workflow instance to its next state.

  If the instance is `:pending`, it is started by activating the workflow's
  initial step. If the instance is `:waiting` or has active steps still
  running, it is returned unchanged. Otherwise, completion is checked and the
  instance may transition to `:completed`.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct

  ## Returns

    * `{:ok, instance}` - the (possibly updated) instance
    * `{:error, reason}` - if advancing fails

  ## Examples

      iex> instance = Instance.new(MyApp.Workflows.OrderFlow, 1, %{order_id: 123})
      iex> {:ok, advanced} = Engine.advance(instance)
      iex> advanced.status
      :running
      iex> MapSet.member?(advanced.active_steps, MyApp.Steps.ValidateOrder)
      true

  A `:waiting` instance is returned unchanged:

      iex> {:ok, ^waiting_instance} = Engine.advance(waiting_instance)
  """
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

  @doc """
  Executes a step module's `c:Hephaestus.Step.execute/3` callback.

  Looks up the step's configuration from the instance and delegates to
  `step_module.execute/3`, passing the instance, its config, and the current
  context.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct
    * `step_module` - the step module to execute (must implement `execute/3`)

  ## Returns

    * `{:ok, event}` - step completed synchronously with the given event atom
    * `{:ok, event, context_updates}` - step completed with context updates
    * `{:ok, event, context_updates, metadata_updates}` - step completed with context and runtime metadata updates
    * `{:async}` - step will complete asynchronously (instance enters `:waiting`)
    * `{:error, reason}` - step execution failed

  ## Examples

      iex> {:ok, instance} = Engine.advance(instance)
      iex> {:ok, :done} = Engine.execute_step(instance, MyApp.Steps.ValidateOrder)

  A step may return context updates along with the event:

      iex> {:ok, :done, %{item_count: 3}} = Engine.execute_step(instance, MyApp.Steps.ProcessOrder)

  Asynchronous steps return `{:async}`:

      iex> {:async} = Engine.execute_step(instance, MyApp.Steps.WaitForPayment)
  """
  @spec execute_step(Instance.t(), module()) ::
          {:ok, atom()}
          | {:ok, atom(), map()}
          | {:ok, atom(), map(), map()}
          | {:async}
          | {:error, term()}
  def execute_step(%Instance{} = instance, step_module) when is_atom(step_module) do
    ensure_module_loaded(step_module)

    unless function_exported?(step_module, :execute, 3) do
      raise "#{inspect(step_module)} must implement execute/3"
    end

    config = Map.get(instance.step_configs, step_module)
    step_module.execute(instance, config, instance.context)
  end

  @doc """
  Marks a step as completed and stores its context updates.

  Moves `step_module` from the active set to the completed set, merges
  `context_updates` into the instance context under the step's context key,
  and removes the step's runtime configuration.

  When `metadata_updates` is provided, merges them into the instance's
  `runtime_metadata` map for observability purposes.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct
    * `step_module` - the step module that finished
    * `event` - the completion event atom (unused internally, passed through
      for consistency)
    * `context_updates` - a map of results to store in the instance context
    * `metadata_updates` - an optional map of runtime metadata to merge
      into the instance (default: `%{}`)

  ## Returns

  The updated `Hephaestus.Core.Instance` struct.

  ## Examples

      iex> instance = Engine.complete_step(instance, MyApp.Steps.ValidateOrder, :done, %{item_count: 3})
      iex> MapSet.member?(instance.completed_steps, MyApp.Steps.ValidateOrder)
      true
      iex> instance.context.steps.validate_order.item_count
      3

  With runtime metadata:

      iex> instance = Engine.complete_step(instance, MyApp.Steps.ProcessOrder, :done, %{total: 100}, %{"order_id" => 42})
      iex> instance.runtime_metadata
      %{"order_id" => 42}
  """
  @spec complete_step(Instance.t(), module(), atom(), map(), map()) :: Instance.t()
  def complete_step(instance, step_module, event, context_updates, metadata_updates \\ %{})

  def complete_step(
        %Instance{} = instance,
        step_module,
        _event,
        context_updates,
        metadata_updates
      )
      when is_atom(step_module) and is_map(context_updates) and is_map(metadata_updates) do
    context_key = module_to_context_key(step_module)

    %{
      instance
      | active_steps: MapSet.delete(instance.active_steps, step_module),
        completed_steps: MapSet.put(instance.completed_steps, step_module),
        context: Context.put_step_result(instance.context, context_key, context_updates),
        runtime_metadata: Map.merge(instance.runtime_metadata, metadata_updates),
        step_configs: Map.delete(instance.step_configs, step_module)
    }
  end

  @doc """
  Resumes a waiting workflow instance after an asynchronous step completes.

  Completes the given step, activates any outgoing transitions for `event`,
  and sets the instance status back to `:running`. If the instance is not in
  the `:waiting` status, it is returned unchanged.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct (must be `:waiting`)
    * `step_module` - the step module that produced the resume event
    * `event` - the event atom that triggered the resume

  ## Returns

  The updated `Hephaestus.Core.Instance` struct.

  ## Examples

      iex> instance = Engine.resume_step(waiting_instance, MyApp.Steps.WaitForPayment, :payment_confirmed)
      iex> instance.status
      :running

  If the instance is not `:waiting`, it is returned unchanged:

      iex> running_instance = Engine.resume_step(running_instance, MyApp.Steps.SomeStep, :done)
      iex> running_instance.status
      :running
  """
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

  @doc """
  Checks whether the workflow instance has completed.

  If there are no active steps and the instance is not `:waiting`, the status
  is set to `:completed` and `current_step` is cleared. Otherwise, the
  instance is returned unchanged.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct

  ## Returns

  The (possibly updated) `Hephaestus.Core.Instance` struct.
  """
  @spec check_completion(Instance.t()) :: Instance.t()
  def check_completion(%Instance{active_steps: active_steps} = instance) do
    if MapSet.size(active_steps) == 0 and instance.status != :waiting do
      %{instance | status: :completed, current_step: nil}
    else
      instance
    end
  end

  @doc """
  Resolves and activates outgoing transitions from a completed step.

  Calls the workflow's `transit/3` callback to determine the next step(s)
  for the given `from_module` and `event`. Each target step is activated only
  if all of its predecessors have already completed (join semantics).

  Supports single targets, `{target, config}` tuples, and lists of targets
  for parallel fan-out.

  ## Parameters

    * `instance` - a `Hephaestus.Core.Instance` struct
    * `from_module` - the step module that just completed
    * `event` - the event atom returned by the completed step

  ## Returns

  The updated `Hephaestus.Core.Instance` struct with newly activated steps.
  """
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
    try do
      workflow.transit(from_module, event, instance.context)
    rescue
      error in FunctionClauseError ->
        if error.module == workflow and error.function == :transit and error.arity == 3 do
          nil
        else
          reraise(error, __STACKTRACE__)
        end
    end
  end

  defp maybe_activate_step(%Instance{} = instance, step_module, config)
       when is_atom(step_module) do
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
