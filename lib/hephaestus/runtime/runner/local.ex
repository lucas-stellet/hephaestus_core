defmodule Hephaestus.Runtime.Runner.Local do
  @moduledoc """
  Local OTP runner that executes one workflow instance per GenServer process.
  """

  use GenServer

  alias Hephaestus.Core.{Engine, Instance}
  alias Hephaestus.Runtime.Runner
  alias Hephaestus.StepDefinition

  @behaviour Runner

  @locator_table __MODULE__.Locator

  @type state :: %{
          instance: Instance.t(),
          storage: {module(), term()},
          task_supervisor: GenServer.server()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    instance = Keyword.fetch!(opts, :instance)
    registry = Keyword.fetch!(opts, :registry)
    storage = Keyword.fetch!(opts, :storage)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)

    GenServer.start_link(
      __MODULE__,
      %{instance: instance, storage: storage, task_supervisor: task_supervisor},
      name: via_tuple(registry, instance.id)
    )
  end

  @impl Runner
  @spec start_instance(module(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_instance(workflow, context, opts) when is_atom(workflow) and is_map(context) do
    storage = Keyword.fetch!(opts, :storage)
    registry = Keyword.fetch!(opts, :registry)
    dynamic_supervisor = Keyword.fetch!(opts, :dynamic_supervisor)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)

    instance = Instance.new(workflow, context)
    :ok = storage_put(storage, instance)
    put_locator(instance.id, registry)

    child_spec = %{
      id: {__MODULE__, instance.id},
      start: {__MODULE__, :start_link, [[instance: instance, registry: registry, storage: storage, task_supervisor: task_supervisor]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(dynamic_supervisor, child_spec) do
      {:ok, _pid} -> {:ok, instance.id}
      {:error, reason} ->
        delete_locator(instance.id)
        {:error, reason}
    end
  end

  @impl Runner
  @spec resume(String.t(), String.t()) :: :ok | {:error, :instance_not_found}
  def resume(instance_id, event) when is_binary(instance_id) and is_binary(event) do
    with {:ok, pid} <- lookup_instance(instance_id) do
      GenServer.cast(pid, {:resume, event})
      :ok
    end
  end

  @impl Runner
  @spec schedule_resume(String.t(), atom(), pos_integer()) ::
          {:ok, reference()} | {:error, :instance_not_found}
  def schedule_resume(instance_id, step_ref, delay_ms)
      when is_binary(instance_id) and is_atom(step_ref) and is_integer(delay_ms) and delay_ms > 0 do
    with {:ok, pid} <- lookup_instance(instance_id) do
      {:ok, Process.send_after(pid, {:scheduled_resume, step_ref}, delay_ms)}
    end
  end

  @impl GenServer
  @spec init(state()) :: {:ok, state(), {:continue, :advance}}
  def init(state) do
    {:ok, state, {:continue, :advance}}
  end

  @impl GenServer
  def handle_continue(:advance, %{instance: %Instance{status: :waiting}} = state) do
    {:noreply, state}
  end

  def handle_continue(:advance, %{instance: instance} = state) do
    instance = ensure_started(instance)

    case MapSet.size(instance.active_steps) do
      0 ->
        state
        |> with_instance(maybe_complete(instance))
        |> persist_instance()
        |> reply_or_stop()

      1 ->
        instance
        |> execute_single_step(state)
        |> persist_instance()
        |> reply_or_stop()

      _many ->
        next_state =
          state
          |> with_instance(%{instance | status: :running, current_step: nil})
          |> persist_instance()

        {:noreply, next_state, {:continue, :execute_active}}
    end
  end

  def handle_continue(:execute_active, %{instance: instance, task_supervisor: task_supervisor} = state) do
    results =
      instance.active_steps
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn step_ref ->
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          {step_ref, execute_step(instance, step_ref)}
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    next_instance =
      Enum.reduce_while(results, %{instance | status: :running, current_step: nil}, fn
        {step_ref, {:ok, event}}, acc ->
          {:cont, acc |> Engine.complete_step(step_ref, event, %{}) |> activate_transitions(step_ref, event)}

        {step_ref, {:ok, event, context_updates}}, acc ->
          {:cont,
           acc
           |> Engine.complete_step(step_ref, event, context_updates)
           |> activate_transitions(step_ref, event)}

        {step_ref, {:async}}, acc ->
          {:cont, %{acc | status: :waiting, current_step: step_ref}}

        {_step_ref, {:error, reason}}, _acc ->
          {:halt, %{instance | status: :failed, current_step: nil, active_steps: MapSet.new(), execution_history: instance.execution_history ++ []} |> Map.put(:failure_reason, reason)}
      end)
      |> maybe_complete()
      |> Map.drop([:failure_reason])

    next_state =
      state
      |> with_instance(next_instance)
      |> persist_instance()

    reply_or_stop(next_state)
  end

  @impl GenServer
  def handle_cast({:resume, event}, %{instance: instance} = state) do
    next_state =
      state
      |> with_instance(Engine.resume(instance, event))
      |> persist_instance()

    {:noreply, next_state, {:continue, :advance}}
  end

  @impl GenServer
  def handle_info({:scheduled_resume, step_ref}, %{instance: %Instance{current_step: step_ref}} = state) do
    next_state =
      state
      |> with_instance(Engine.resume(state.instance, "timeout"))
      |> persist_instance()

    {:noreply, next_state, {:continue, :advance}}
  end

  def handle_info({:scheduled_resume, _step_ref}, state) do
    {:noreply, state}
  end

  def handle_info(:stop_runner, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, %{instance: %Instance{id: instance_id}}) do
    delete_locator(instance_id)
    :ok
  end

  defp execute_single_step(instance, state) do
    [step_ref] = instance.active_steps |> MapSet.to_list() |> Enum.sort()
    running_instance = %{instance | current_step: step_ref, status: :running}

    state
    |> with_instance(running_instance)
    |> persist_instance()
    |> Map.fetch!(:instance)
    |> execute_step(step_ref)
    |> case do
      {:ok, event} ->
        running_instance
        |> Engine.complete_step(step_ref, event, %{})
        |> activate_transitions(step_ref, event)
        |> maybe_complete()
        |> then(&with_instance(state, &1))

      {:ok, event, context_updates} ->
        running_instance
        |> Engine.complete_step(step_ref, event, context_updates)
        |> activate_transitions(step_ref, event)
        |> maybe_complete()
        |> then(&with_instance(state, &1))

      {:async} ->
        with_instance(state, %{running_instance | status: :waiting})

      {:error, _reason} ->
        with_instance(state, %{running_instance | status: :failed, active_steps: MapSet.new()})
    end
  end

  defp execute_step(instance, step_ref) do
    step_ref
    |> instance.workflow.__step__()
    |> then(&Engine.execute_step(instance, &1))
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

  defp maybe_complete(%Instance{active_steps: active_steps, status: status} = instance) do
    if MapSet.size(active_steps) == 0 and status != :waiting do
      %{instance | status: :completed, current_step: nil}
    else
      instance
    end
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

  defp persist_instance(%{instance: instance, storage: storage} = state) do
    :ok = storage_put(storage, instance)
    state
  end

  defp reply_or_stop(%{instance: %Instance{status: :completed}} = state) do
    Process.send_after(self(), :stop_runner, 0)
    {:noreply, state}
  end

  defp reply_or_stop(%{instance: %Instance{status: :failed}} = state) do
    Process.send_after(self(), :stop_runner, 0)
    {:noreply, state}
  end

  defp reply_or_stop(%{instance: %Instance{status: :running}} = state) do
    {:noreply, state, {:continue, :advance}}
  end

  defp reply_or_stop(state) do
    {:noreply, state}
  end

  defp with_instance(state, instance), do: %{state | instance: instance}

  defp via_tuple(registry, instance_id) do
    {:via, Registry, {registry, instance_id}}
  end

  defp lookup_instance(instance_id) do
    with registry when not is_nil(registry) <- get_locator(instance_id),
         [{pid, _value}] <- Registry.lookup(registry, instance_id) do
      {:ok, pid}
    else
      _ -> {:error, :instance_not_found}
    end
  end

  defp storage_put({storage_module, storage_name}, instance) do
    apply(storage_module, :put, [storage_name, instance])
  end

  defp ensure_locator_table do
    case :ets.whereis(@locator_table) do
      :undefined ->
        :ets.new(@locator_table, [:named_table, :public, :set, read_concurrency: true])

      _table ->
        @locator_table
    end
  end

  defp put_locator(instance_id, registry) do
    table = ensure_locator_table()
    true = :ets.insert(table, {instance_id, registry})
    :ok
  end

  defp get_locator(instance_id) do
    table = ensure_locator_table()

    case :ets.lookup(table, instance_id) do
      [{^instance_id, registry}] -> registry
      [] -> nil
    end
  end

  defp delete_locator(instance_id) do
    table = ensure_locator_table()
    true = :ets.delete(table, instance_id)
    :ok
  end
end
