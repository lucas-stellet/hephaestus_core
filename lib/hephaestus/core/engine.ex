defmodule Hephaestus.Core.Engine do
  alias Hephaestus.Core.{Context, ExecutionEntry, Instance}
  alias Hephaestus.StepDefinition

  @spec advance(Instance.t()) :: {:ok, Instance.t()} | {:error, term()}
  def advance(%Instance{} = instance) do
    instance
    |> ensure_started()
    |> do_advance()
  end

  @spec execute_step(Instance.t(), term()) ::
          {:ok, String.t()} | {:ok, String.t(), map()} | {:async} | {:error, term()}
  def execute_step(%Instance{} = instance, step_def) do
    step_module = StepDefinition.module(step_def)
    config = StepDefinition.config(step_def)

    step_module.execute(instance, config, instance.context)
  end

  @spec complete_step(Instance.t(), atom(), String.t(), map()) :: Instance.t()
  def complete_step(%Instance{} = instance, step_ref, event, context_updates) do
    entry = %ExecutionEntry{
      step_ref: step_ref,
      event: event,
      timestamp: DateTime.utc_now(),
      context_updates: context_updates
    }

    %{
      instance
      | active_steps: MapSet.delete(instance.active_steps, step_ref),
        completed_steps: MapSet.put(instance.completed_steps, step_ref),
        context: Context.put_step_result(instance.context, step_ref, context_updates),
        execution_history: instance.execution_history ++ [entry]
    }
  end

  @spec resume(Instance.t(), String.t()) :: Instance.t()
  def resume(%Instance{status: :waiting, current_step: step_ref} = instance, event)
      when is_atom(step_ref) and is_binary(event) do
    instance
    |> complete_step(step_ref, event, %{})
    |> activate_transitions(step_ref, event)
    |> Map.put(:status, :running)
    |> Map.put(:current_step, nil)
  end

  def resume(%Instance{} = instance, _event), do: instance

  defp do_advance(%Instance{status: :waiting} = instance), do: {:ok, instance}

  defp do_advance(%Instance{} = instance) do
    case next_active_step(instance) do
      nil ->
        {:ok, maybe_complete(instance)}

      step_ref ->
        step_def = instance.workflow.__step__(step_ref)
        running_instance = %{instance | current_step: step_ref, status: :running}

        case execute_step(running_instance, step_def) do
          {:ok, event} ->
            running_instance
            |> complete_step(step_ref, event, %{})
            |> activate_transitions(step_ref, event)
            |> do_advance()

          {:ok, event, context_updates} ->
            running_instance
            |> complete_step(step_ref, event, context_updates)
            |> activate_transitions(step_ref, event)
            |> do_advance()

          {:async} ->
            {:ok, %{running_instance | status: :waiting}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

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

  defp maybe_complete(%Instance{active_steps: active_steps} = instance) do
    if MapSet.size(active_steps) == 0 and instance.status != :waiting do
      %{instance | status: :completed, current_step: nil}
    else
      instance
    end
  end

  defp next_active_step(%Instance{active_steps: active_steps}) do
    active_steps
    |> MapSet.to_list()
    |> Enum.sort()
    |> List.first()
  end

  defp activate_transitions(%Instance{} = instance, step_ref, event) do
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
