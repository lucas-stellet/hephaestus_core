defmodule Hephaestus.Core.Engine do
  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.StepDefinition

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

  @spec execute_step(Instance.t(), term()) ::
          {:ok, String.t()} | {:ok, String.t(), map()} | {:async} | {:error, term()}
  def execute_step(%Instance{} = instance, step_def) do
    step_module = StepDefinition.module(step_def)
    config = StepDefinition.config(step_def)

    step_module.execute(instance, config, instance.context)
  end

  @spec complete_step(Instance.t(), atom(), String.t(), map()) :: Instance.t()
  def complete_step(%Instance{} = instance, step_ref, _event, context_updates) do
    %{
      instance
      | active_steps: MapSet.delete(instance.active_steps, step_ref),
        completed_steps: MapSet.put(instance.completed_steps, step_ref),
        context: Context.put_step_result(instance.context, step_ref, context_updates)
    }
  end

  @spec resume_step(Instance.t(), atom(), String.t()) :: Instance.t()
  def resume_step(%Instance{status: :waiting} = instance, step_ref, event)
      when is_atom(step_ref) and is_binary(event) do
    instance
    |> complete_step(step_ref, event, %{})
    |> activate_transitions(step_ref, event)
    |> Map.put(:status, :running)
    |> Map.put(:current_step, nil)
  end

  def resume_step(%Instance{} = instance, _step_ref, _event), do: instance

  defp ensure_started(%Instance{status: :pending} = instance) do
    workflow = instance.workflow.definition()

    %{
      instance
      | status: :running,
        current_step: workflow.initial_step,
        active_steps: MapSet.put(instance.active_steps, workflow.initial_step)
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

  @spec activate_transitions(Instance.t(), atom(), String.t()) :: Instance.t()
  def activate_transitions(%Instance{} = instance, step_ref, event) do
    transitions =
      step_ref
      |> instance.workflow.__step__()
      |> StepDefinition.transitions()

    case Map.get(transitions || %{}, event) do
      nil -> instance
      target when is_atom(target) -> maybe_activate_step(instance, target)
      targets when is_list(targets) -> Enum.reduce(targets, instance, &maybe_activate_step(&2, &1))
    end
  end

  defp maybe_activate_step(%Instance{} = instance, step_ref) when is_atom(step_ref) do
    predecessors = instance.workflow.__predecessors__(step_ref)

    if MapSet.subset?(predecessors, instance.completed_steps) do
      %{instance | active_steps: MapSet.put(instance.active_steps, step_ref)}
    else
      instance
    end
  end
end
