defmodule Hephaestus.Runtime.Runner.Local do
  @moduledoc """
  Local OTP runner that executes one workflow instance per GenServer process.

  Crash recovery restores the latest persisted instance state from storage, but
  `schedule_resume/3` timers are process-local and do not survive a runner crash.
  """

  use GenServer

  alias Hephaestus.Core.{Engine, Instance}
  alias Hephaestus.Runtime.Runner
  alias Hephaestus.Telemetry

  @behaviour Runner
  @registry_key {__MODULE__, :registry}

  @type state :: %{
          instance: Instance.t(),
          registry: term(),
          storage: {module(), term()},
          task_supervisor: GenServer.server(),
          advance_count: non_neg_integer(),
          step_count: non_neg_integer(),
          waiting_since: integer() | nil
        }

  @doc """
  Starts and links a local runner GenServer for the given workflow instance.

  ## Options

    * `:instance` (required) — the `Hephaestus.Core.Instance` struct to execute.
    * `:instance_id` — overrides the instance's own ID for registry lookup (defaults to `instance.id`).
    * `:registry` — the `Registry` used for process name registration.
    * `:storage` — a `{module, name}` tuple for the storage adapter.
    * `:task_supervisor` — the `Task.Supervisor` used to run step executions concurrently.
  """
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

  @doc """
  Creates a new workflow instance and spawns a local GenServer to execute it.

  The instance is persisted to storage immediately, then a transient child is
  started under the given `DynamicSupervisor`. The runner process registers
  itself in the provided `Registry` so it can be located by instance ID.

  ## Options

    * `:storage` — a `{module, name}` tuple for the storage adapter.
    * `:registry` — the `Registry` used for process name registration.
    * `:dynamic_supervisor` — the `DynamicSupervisor` that will own the runner process.
    * `:task_supervisor` — the `Task.Supervisor` used to run step executions concurrently.
  """
  @impl Runner
  @spec start_instance(module(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_instance(workflow, context, opts) when is_atom(workflow) and is_map(context) do
    storage = Keyword.fetch!(opts, :storage)
    registry = Keyword.fetch!(opts, :registry)
    dynamic_supervisor = Keyword.fetch!(opts, :dynamic_supervisor)
    task_supervisor = Keyword.fetch!(opts, :task_supervisor)
    telemetry_metadata = Keyword.get(opts, :telemetry_metadata, %{})
    remember_registry(registry)

    instance = %{Instance.new(workflow, context) | telemetry_metadata: telemetry_metadata}
    :ok = storage_put(storage, instance)

    child_spec = %{
      id: {__MODULE__, instance.id},
      start:
        {__MODULE__, :start_link,
         [
           [
             instance: instance,
             instance_id: instance.id,
             registry: registry,
             storage: storage,
             task_supervisor: task_supervisor
           ]
         ]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(dynamic_supervisor, child_spec) do
      {:ok, _pid} -> {:ok, instance.id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resumes a waiting instance by sending an asynchronous cast to its runner process.

  The event is normalized to an atom and delivered via `GenServer.cast/2`, so the
  call returns immediately. Returns `{:error, :instance_not_found}` if no runner
  process is registered for the given `instance_id`.
  """
  @impl Runner
  @spec resume(String.t(), atom() | String.t()) :: :ok | {:error, :instance_not_found}
  def resume(instance_id, event)
      when is_binary(instance_id) and (is_binary(event) or is_atom(event)) do
    with {:ok, pid} <- lookup_instance(instance_id) do
      GenServer.cast(pid, {:resume, normalize_event(event)})
      :ok
    end
  end

  @doc """
  Schedules a delayed `:timeout` resume for a specific step using `Process.send_after/3`.

  Because the timer is process-local, it does **not** survive a runner crash.
  Returns `{:ok, timer_ref}` on success, where `timer_ref` is the Erlang timer
  reference that can be cancelled with `Process.cancel_timer/1`.
  """
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
  def init(
        %{instance: instance, instance_id: instance_id, registry: registry, storage: storage} =
          state
      ) do
    remember_registry(registry)

    recovered_instance = recover_instance(storage, instance_id, instance)

    case recovered_instance.status do
      status when status in [:completed, :failed] ->
        {:stop, :normal}

      _ ->
        instrumented_instance = %{
          recovered_instance
          | telemetry_start_time: System.monotonic_time()
        }

        initial_step = instrumented_instance.workflow.start()
        initial_step_module = normalize_start_target(initial_step)

        context_keys =
          case instrumented_instance.context do
            %{initial: initial} when is_map(initial) -> Map.keys(initial)
            _ -> []
          end

        Telemetry.workflow_start(instrumented_instance, %{
          initial_step: initial_step_module,
          runner: __MODULE__,
          context_keys: context_keys
        })

        state =
          state
          |> with_instance(instrumented_instance)
          |> Map.put(:advance_count, 0)
          |> Map.put(:step_count, 0)
          |> Map.put(:waiting_since, nil)

        {:ok, state, {:continue, :advance}}
    end
  end

  @impl GenServer
  def handle_continue(:advance, %{instance: instance} = state) do
    status_before = instance.status
    advance_start = System.monotonic_time()

    {:ok, next_instance} = Engine.advance(instance)

    advance_duration = System.monotonic_time() - advance_start
    advance_count = state.advance_count + 1

    Telemetry.engine_advance(next_instance, advance_duration, %{
      status_before: status_before,
      status_after: next_instance.status,
      active_steps_count: MapSet.size(next_instance.active_steps),
      completed_in_advance:
        MapSet.size(next_instance.completed_steps) - MapSet.size(instance.completed_steps),
      iteration: advance_count
    })

    state = %{state | advance_count: advance_count}

    case next_instance do
      %Instance{status: :completed} ->
        state
        |> with_instance(next_instance)
        |> persist_instance()
        |> emit_workflow_stop()
        |> reply_or_stop()

      %Instance{status: :waiting} ->
        next_state =
          state
          |> with_instance(next_instance)
          |> Map.put(:waiting_since, System.monotonic_time())
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

  def handle_continue(
        :execute_active,
        %{instance: instance, task_supervisor: task_supervisor} = state
      ) do
    active_steps_count = MapSet.size(instance.active_steps)
    concurrent = active_steps_count > 1

    results =
      instance.active_steps
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.map(fn step_ref ->
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          {step_ref,
           execute_step_with_telemetry(instance, step_ref, concurrent, active_steps_count)}
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    {next_instance, step_count} =
      Enum.reduce_while(
        results,
        {%{instance | status: :running, current_step: nil}, state.step_count},
        fn
          {step_ref, {:ok, event}}, {acc, sc} ->
            completed =
              acc
              |> Engine.complete_step(step_ref, event, %{})
              |> Engine.activate_transitions(step_ref, event)

            targets = get_activated_targets(acc, completed, step_ref)
            Telemetry.workflow_transition(completed, step_ref, event, targets, %{})

            {:cont, {completed, sc + 1}}

          {step_ref, {:ok, event, context_updates}}, {acc, sc} ->
            completed =
              acc
              |> Engine.complete_step(step_ref, event, context_updates)
              |> Engine.activate_transitions(step_ref, event)

            targets = get_activated_targets(acc, completed, step_ref)
            Telemetry.workflow_transition(completed, step_ref, event, targets, %{})

            {:cont, {completed, sc + 1}}

          {step_ref, {:ok, event, context_updates, metadata_updates}}, {acc, sc} ->
            completed =
              acc
              |> Engine.complete_step(step_ref, event, context_updates, metadata_updates)
              |> Engine.activate_transitions(step_ref, event)

            targets = get_activated_targets(acc, completed, step_ref)
            Telemetry.workflow_transition(completed, step_ref, event, targets, %{})

            {:cont, {completed, sc + 1}}

          {step_ref, {:async}}, {acc, sc} ->
            {:cont, {%{acc | status: :waiting, current_step: step_ref}, sc}}

          {step_ref, {:error, reason}}, {acc, sc} ->
            failed = %{acc | status: :failed, current_step: nil, active_steps: MapSet.new()}

            Telemetry.workflow_exception(failed, :error, reason, nil, %{
              failed_step: step_ref,
              step_count: sc,
              advance_count: state.advance_count,
              runner: __MODULE__
            })

            {:halt, {failed, sc}}
        end
      )

    state = %{state | step_count: step_count}

    next_instance =
      case next_instance do
        %Instance{status: :failed} -> next_instance
        other -> Engine.check_completion(other)
      end

    next_state =
      state
      |> with_instance(next_instance)
      |> maybe_set_waiting_since()
      |> persist_instance()

    case next_instance do
      %Instance{status: :completed} ->
        next_state
        |> emit_workflow_stop()
        |> reply_or_stop()

      _ ->
        reply_or_stop(next_state)
    end
  end

  @impl GenServer
  def handle_cast({:resume, event}, %{instance: instance} = state) do
    wait_duration = compute_wait_duration(state.waiting_since)
    step = instance.current_step

    Telemetry.step_resume(instance, step, %{
      step_key: step,
      resume_event: event,
      source: :external,
      wait_duration: wait_duration
    })

    next_state =
      state
      |> with_instance(Engine.resume_step(instance, instance.current_step, event))
      |> Map.put(:waiting_since, nil)
      |> persist_instance()

    {:noreply, next_state, {:continue, :advance}}
  end

  @impl GenServer
  def handle_info({:scheduled_resume, step_ref}, %{instance: instance} = state) do
    wait_duration = compute_wait_duration(state.waiting_since)

    Telemetry.step_resume(instance, step_ref, %{
      step_key: step_ref,
      resume_event: :timeout,
      source: :timeout,
      wait_duration: wait_duration
    })

    next_state =
      state
      |> with_instance(Engine.resume_step(instance, step_ref, :timeout))
      |> Map.put(:waiting_since, nil)
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

  defp execute_step_with_telemetry(instance, step_ref, concurrent, active_steps_count) do
    Telemetry.step_start(instance, step_ref, %{
      step_key: step_ref,
      concurrent: concurrent,
      active_steps_count: active_steps_count
    })

    start_time = System.monotonic_time()

    try do
      result = Engine.execute_step(instance, step_ref)
      duration = System.monotonic_time() - start_time

      case result do
        {:ok, event} ->
          Telemetry.step_stop(instance, step_ref, duration, %{
            step_key: step_ref,
            event: event,
            has_context_updates: false,
            has_metadata_updates: false
          })

          result

        {:ok, event, _context_updates} ->
          Telemetry.step_stop(instance, step_ref, duration, %{
            step_key: step_ref,
            event: event,
            has_context_updates: true,
            has_metadata_updates: false
          })

          result

        {:ok, event, _context_updates, _metadata_updates} ->
          Telemetry.step_stop(instance, step_ref, duration, %{
            step_key: step_ref,
            event: event,
            has_context_updates: true,
            has_metadata_updates: true
          })

          result

        {:async} ->
          Telemetry.step_async(instance, step_ref, duration, %{
            step_key: step_ref,
            instance_status: :waiting
          })

          result

        {:error, reason} ->
          Telemetry.step_exception(instance, step_ref, duration, :error, reason, nil, %{
            step_key: step_ref
          })

          result
      end
    rescue
      exception ->
        duration = System.monotonic_time() - start_time

        Telemetry.step_exception(
          instance,
          step_ref,
          duration,
          :error,
          exception,
          __STACKTRACE__,
          %{step_key: step_ref}
        )

        reraise exception, __STACKTRACE__
    end
  end

  defp normalize_event(event) when is_atom(event), do: event
  defp normalize_event(event) when is_binary(event), do: String.to_existing_atom(event)

  defp normalize_start_target({step, _opts}), do: step
  defp normalize_start_target(step) when is_atom(step), do: step

  defp emit_workflow_stop(%{instance: instance} = state) do
    Telemetry.workflow_stop(instance, %{
      step_count: state.step_count,
      advance_count: state.advance_count,
      completed_steps: MapSet.to_list(instance.completed_steps),
      runner: __MODULE__
    })

    state
  end

  defp get_activated_targets(before_instance, after_instance, _step_ref) do
    new_active = MapSet.difference(after_instance.active_steps, before_instance.active_steps)
    MapSet.to_list(new_active)
  end

  defp maybe_set_waiting_since(%{instance: %Instance{status: :waiting}} = state) do
    %{state | waiting_since: System.monotonic_time()}
  end

  defp maybe_set_waiting_since(state), do: state

  defp compute_wait_duration(nil), do: nil
  defp compute_wait_duration(waiting_since), do: System.monotonic_time() - waiting_since

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
