defmodule Hephaestus.Runtime.Runner.Local do
  @moduledoc """
  Local OTP runner that executes one workflow instance per GenServer process.

  Crash recovery restores the latest persisted instance state from storage, but
  `schedule_resume/3` timers are process-local and do not survive a runner crash.
  """

  use GenServer

  alias Hephaestus.Core.{Engine, Instance}
  alias Hephaestus.Runtime.Runner

  @behaviour Runner
  @registry_key {__MODULE__, :registry}

  @type state :: %{
          instance: Instance.t(),
          registry: term(),
          storage: {module(), term()},
          task_supervisor: GenServer.server()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    instance = Keyword.fetch!(opts, :instance)
    instance_id = Keyword.get(opts, :instance_id, instance.id)
    registry = Keyword.fetch!(opts, :registry)
    storage = Keyword.fetch!(opts, :storage)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)

    remember_registry(registry)

    GenServer.start_link(
      __MODULE__,
      %{
        instance: instance,
        instance_id: instance_id,
        registry: registry,
        storage: storage,
        task_supervisor: task_supervisor
      },
      name: via_tuple(registry, instance_id)
    )
  end

  @impl Runner
  @spec start_instance(module(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_instance(workflow, context, opts) when is_atom(workflow) and is_map(context) do
    storage = Keyword.fetch!(opts, :storage)
    registry = Keyword.fetch!(opts, :registry)
    dynamic_supervisor = Keyword.fetch!(opts, :dynamic_supervisor)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)
    remember_registry(registry)

    instance = Instance.new(workflow, context)
    :ok = storage_put(storage, instance)

    child_spec = %{
      id: {__MODULE__, instance.id},
      start:
        {__MODULE__, :start_link,
         [[
           instance: instance,
           instance_id: instance.id,
           registry: registry,
           storage: storage,
           task_supervisor: task_supervisor
         ]]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(dynamic_supervisor, child_spec) do
      {:ok, _pid} -> {:ok, instance.id}
      {:error, reason} -> {:error, reason}
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
  @spec init(state()) :: {:ok, state(), {:continue, :advance}} | {:stop, :normal}
  def init(%{instance: instance, instance_id: instance_id, registry: registry, storage: storage} = state) do
    remember_registry(registry)

    recovered_instance = recover_instance(storage, instance_id, instance)

    case recovered_instance.status do
      status when status in [:completed, :failed] ->
        {:stop, :normal}

      _ ->
        {:ok, with_instance(state, recovered_instance), {:continue, :advance}}
    end
  end

  @impl GenServer
  def handle_continue(:advance, %{instance: instance} = state) do
    {:ok, next_instance} = Engine.advance(instance)

    case next_instance do
      %Instance{status: :completed} ->
        state
        |> with_instance(next_instance)
        |> persist_instance()
        |> reply_or_stop()

      %Instance{status: :waiting} ->
        next_state =
          state
          |> with_instance(next_instance)
          |> persist_instance()

        {:noreply, next_state}

      %Instance{status: :running, active_steps: active_steps} ->
        next_state =
          state
          |> with_instance(next_instance)
          |> persist_instance()

        if MapSet.size(active_steps) > 0 do
          {:noreply, next_state, {:continue, :execute_active}}
        else
          {:noreply, next_state}
        end
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
          {:cont, acc |> Engine.complete_step(step_ref, event, %{}) |> Engine.activate_transitions(step_ref, event)}

        {step_ref, {:ok, event, context_updates}}, acc ->
          {:cont,
           acc
           |> Engine.complete_step(step_ref, event, context_updates)
           |> Engine.activate_transitions(step_ref, event)}

        {step_ref, {:async}}, acc ->
          {:cont, %{acc | status: :waiting, current_step: step_ref}}

        {_step_ref, {:error, _reason}}, acc ->
          {:halt, %{acc | status: :failed, current_step: nil, active_steps: MapSet.new()}}
      end)
      |> then(fn
        %Instance{status: :failed} = failed_instance -> failed_instance
        next_instance -> Engine.check_completion(next_instance)
      end)

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
      |> with_instance(Engine.resume_step(instance, instance.current_step, event))
      |> persist_instance()

    {:noreply, next_state, {:continue, :advance}}
  end

  @impl GenServer
  def handle_info({:scheduled_resume, step_ref}, %{instance: instance} = state) do
    next_state =
      state
      |> with_instance(Engine.resume_step(instance, step_ref, "timeout"))
      |> persist_instance()

    {:noreply, next_state, {:continue, :advance}}
  end

  def handle_info(:stop_runner, state) do
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    :ok
  end

  defp execute_step(instance, step_ref) do
    step_ref
    |> instance.workflow.__step__()
    |> then(&Engine.execute_step(instance, &1))
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
    with registry when not is_nil(registry) <- remembered_registry(),
         true <- Process.whereis(registry) != nil,
         [{pid, _value}] <- Registry.lookup(registry, instance_id) do
      {:ok, pid}
    else
      _ -> {:error, :instance_not_found}
    end
  end

  defp storage_put({storage_module, storage_name}, instance) do
    apply(storage_module, :put, [storage_name, instance])
  end

  defp recover_instance(storage, instance_id, instance) do
    case storage_get(storage, instance_id) do
      {:ok, %Instance{status: status} = stored_instance} when status != :pending ->
        stored_instance

      _ ->
        instance
    end
  end

  defp storage_get({storage_module, storage_name}, instance_id) do
    apply(storage_module, :get, [storage_name, instance_id])
  end

  defp remember_registry(registry), do: :persistent_term.put(@registry_key, registry)

  defp remembered_registry, do: :persistent_term.get(@registry_key, nil)
end
