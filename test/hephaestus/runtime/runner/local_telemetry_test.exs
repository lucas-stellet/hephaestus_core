defmodule Hephaestus.Runtime.Runner.LocalTelemetryTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Runtime.Runner.Local, as: RunnerLocal
  alias Hephaestus.Runtime.Storage.ETS, as: ETSStorage

  setup do
    test_pid = self()
    name = :"telemetry_test_#{System.unique_integer([:positive])}"

    registry = Module.concat(name, Registry)
    dynamic_supervisor = Module.concat(name, DynamicSupervisor)
    task_supervisor = Module.concat(name, TaskSupervisor)
    storage_name = Module.concat(name, Storage)

    children = [
      {Registry, keys: :unique, name: registry},
      {DynamicSupervisor, name: dynamic_supervisor, strategy: :one_for_one},
      {Task.Supervisor, name: task_supervisor},
      {ETSStorage, name: storage_name}
    ]

    {:ok, _sup} = Supervisor.start_link(children, strategy: :one_for_one)

    handler_id = "telemetry-test-#{inspect(test_pid)}-#{System.unique_integer([:positive])}"

    handler = fn event, measurements, metadata, _config ->
      send(test_pid, {:telemetry, event, measurements, metadata})
    end

    :telemetry.attach_many(handler_id, Hephaestus.Telemetry.events(), handler, nil)
    on_exit(fn -> :telemetry.detach(handler_id) end)

    opts = [
      storage: {ETSStorage, storage_name},
      registry: registry,
      dynamic_supervisor: dynamic_supervisor,
      task_supervisor: task_supervisor
    ]

    %{opts: opts, storage: storage_name}
  end

  describe "linear workflow telemetry" do
    test "emits workflow:start with instance_id and workflow module", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed))

      assert_receive {:telemetry, [:hephaestus, :workflow, :start], measurements, metadata}, 5000
      assert is_integer(measurements.system_time)
      assert metadata.instance_id == id
      assert metadata.workflow == Hephaestus.Test.V2.LinearWorkflow
    end

    test "emits step:start and step:stop for each step", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed))

      # Drain all messages and collect step events
      messages = drain_telemetry_messages()

      step_starts =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :step, :start]
        end)

      step_stops =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :step, :stop]
        end)

      # LinearWorkflow has StepA -> StepB -> Done, so at least StepA and StepB execute
      assert length(step_starts) >= 2
      assert length(step_stops) >= 2

      assert Enum.all?(step_stops, fn {:telemetry, _, measurements, _} ->
               measurements.duration > 0
             end)
    end

    test "emits workflow:stop with duration and step_count", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed))

      assert_receive {:telemetry, [:hephaestus, :workflow, :stop], measurements, metadata}, 5000
      assert measurements.duration > 0
      assert measurements.step_count > 0
      assert measurements.advance_count > 0
      assert metadata.status == :completed
    end

    test "emits engine:advance events", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed))

      messages = drain_telemetry_messages()

      advance_events =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :engine, :advance]
        end)

      assert length(advance_events) >= 1

      assert Enum.all?(advance_events, fn {:telemetry, _, measurements, _} ->
               measurements.duration > 0
             end)
    end

    test "emits workflow:transition events for each step completion", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed))

      messages = drain_telemetry_messages()

      transitions =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :workflow, :transition]
        end)

      # StepA -> StepB and StepB -> Done transitions
      assert length(transitions) >= 2

      assert Enum.all?(transitions, fn {:telemetry, _, _, metadata} ->
               is_atom(metadata.from_step) and is_atom(metadata.event)
             end)
    end
  end

  describe "fan-out workflow telemetry" do
    test "step:start has concurrent: true for parallel steps", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.FanOutWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed), 2_000)

      messages = drain_telemetry_messages()

      step_starts =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :step, :start]
        end)

      concurrent_starts =
        Enum.filter(step_starts, fn {:telemetry, _, _, metadata} ->
          metadata[:concurrent] == true
        end)

      assert length(concurrent_starts) >= 2

      assert Enum.all?(concurrent_starts, fn {:telemetry, _, _, metadata} ->
               metadata.active_steps_count >= 2
             end)
    end

    test "workflow:transition has fan_out: true for fan-out transition", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.FanOutWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :completed), 2_000)

      messages = drain_telemetry_messages()

      transitions =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          event == [:hephaestus, :workflow, :transition]
        end)

      fan_out_transitions =
        Enum.filter(transitions, fn {:telemetry, _, _, metadata} ->
          metadata[:fan_out] == true
        end)

      assert length(fan_out_transitions) >= 1

      Enum.each(fan_out_transitions, fn {:telemetry, _, measurements, _} ->
        assert measurements.targets_count >= 2
      end)
    end
  end

  describe "async workflow telemetry" do
    test "emits step:async then step:resume on resume", %{opts: opts, storage: storage} do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.AsyncWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :waiting))

      assert_receive {:telemetry, [:hephaestus, :step, :async], async_measurements,
                      async_metadata},
                     5000

      assert async_metadata.instance_status == :waiting
      assert async_measurements.duration > 0

      :ok = RunnerLocal.resume(id, :timeout)
      wait_for_instance(storage, id, &(&1.status == :completed))

      assert_receive {:telemetry, [:hephaestus, :step, :resume], resume_measurements,
                      resume_metadata},
                     5000

      assert resume_metadata.source == :external
      assert resume_metadata.resume_event == :timeout
      assert resume_measurements.wait_duration > 0
    end
  end

  describe "failure telemetry" do
    test "emits step:exception and workflow:exception on step error", %{
      opts: opts,
      storage: storage
    } do
      {:ok, id} = RunnerLocal.start_instance(Hephaestus.Test.V2.FailingWorkflow, %{}, opts)
      wait_for_instance(storage, id, &(&1.status == :failed), 2_000)

      assert_receive {:telemetry, [:hephaestus, :step, :exception], step_measurements,
                      step_metadata},
                     5000

      assert step_metadata.kind == :error
      assert step_metadata.reason == :intentional_failure
      assert step_metadata.step == Hephaestus.Test.V2.FailStep
      assert step_measurements.duration > 0

      assert_receive {:telemetry, [:hephaestus, :workflow, :exception], wf_measurements,
                      wf_metadata},
                     5000

      assert wf_metadata.status == :failed
      assert wf_metadata.failed_step == Hephaestus.Test.V2.FailStep
      assert wf_metadata.kind == :error
      assert wf_metadata.reason == :intentional_failure
      assert is_integer(wf_measurements.duration) or is_nil(wf_measurements.duration)
    end
  end

  describe "telemetry_metadata propagation" do
    test "custom metadata appears in all events", %{opts: opts, storage: storage} do
      opts_with_meta = Keyword.put(opts, :telemetry_metadata, %{request_id: "test-456"})

      {:ok, id} =
        RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts_with_meta)

      wait_for_instance(storage, id, &(&1.status == :completed))

      messages = drain_telemetry_messages()

      # All hephaestus events should have the custom metadata
      hephaestus_events =
        Enum.filter(messages, fn {:telemetry, event, _, _} ->
          match?([:hephaestus | _], event)
        end)

      assert length(hephaestus_events) > 0

      assert Enum.all?(hephaestus_events, fn {:telemetry, _event, _, metadata} ->
               metadata[:request_id] == "test-456"
             end)
    end
  end

  describe "telemetry_metadata override protection" do
    test "Hephaestus fields not overridable by telemetry_metadata", %{
      opts: opts,
      storage: storage
    } do
      opts_with_fake =
        Keyword.put(opts, :telemetry_metadata, %{instance_id: "fake", workflow: "bogus"})

      {:ok, id} =
        RunnerLocal.start_instance(Hephaestus.Test.V2.LinearWorkflow, %{}, opts_with_fake)

      wait_for_instance(storage, id, &(&1.status == :completed))

      assert_receive {:telemetry, [:hephaestus, :workflow, :start], _, metadata}, 5000
      # The real instance_id should win, not "fake"
      assert metadata.instance_id == id
      assert metadata.workflow == Hephaestus.Test.V2.LinearWorkflow
    end
  end

  describe "workflow:stop duration with nil start_time" do
    test "duration is nil when telemetry_start_time is nil", %{opts: _opts, storage: _storage} do
      # Create an instance manually with nil telemetry_start_time
      instance = %{
        Hephaestus.Core.Instance.new(
          Hephaestus.Test.V2.LinearWorkflow,
          1,
          %{},
          "local-telemetry-test-nil-start"
        )
        | telemetry_start_time: nil
      }

      # The Telemetry module's safe_duration/1 returns nil for nil start_time
      # Verify directly through the telemetry module
      # We test this by checking what workflow_stop emits when start_time is nil
      test_pid = self()

      handler_id = "duration-nil-test-#{System.unique_integer([:positive])}"

      handler = fn event, measurements, _metadata, _config ->
        if event == [:hephaestus, :workflow, :stop] do
          send(test_pid, {:stop_duration, measurements.duration})
        end
      end

      :telemetry.attach(handler_id, [:hephaestus, :workflow, :stop], handler, nil)

      Hephaestus.Telemetry.workflow_stop(instance, %{
        step_count: 0,
        advance_count: 0,
        completed_steps: [],
        runner: RunnerLocal
      })

      assert_receive {:stop_duration, nil}, 5000

      :telemetry.detach(handler_id)
    end
  end

  describe "legacy Instance backward compatibility" do
    test "Instance struct defaults telemetry fields", %{storage: storage} do
      instance =
        Hephaestus.Core.Instance.new(
          Hephaestus.Test.V2.LinearWorkflow,
          1,
          %{},
          "local-telemetry-test-defaults"
        )

      # Verify defaults are applied
      assert instance.telemetry_metadata == %{}
      assert instance.telemetry_start_time == nil

      # Store and retrieve
      :ok = ETSStorage.put(storage, instance)
      {:ok, retrieved} = ETSStorage.get(storage, instance.id)

      assert retrieved.telemetry_metadata == %{}
      assert retrieved.telemetry_start_time == nil
    end
  end

  # -- Helpers ----------------------------------------------------------------

  defp drain_telemetry_messages do
    drain_telemetry_messages([])
  end

  defp drain_telemetry_messages(acc) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        drain_telemetry_messages([{:telemetry, event, measurements, metadata} | acc])
    after
      100 ->
        Enum.reverse(acc)
    end
  end

  defp wait_for_instance(storage, id, predicate, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_instance(storage, id, predicate, deadline)
  end

  defp do_wait_for_instance(storage, id, predicate, deadline) do
    case ETSStorage.get(storage, id) do
      {:ok, instance} ->
        if predicate.(instance) do
          instance
        else
          retry_wait(storage, id, predicate, deadline)
        end

      {:error, :not_found} ->
        retry_wait(storage, id, predicate, deadline)
    end
  end

  defp retry_wait(storage, id, predicate, deadline) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(10)
      do_wait_for_instance(storage, id, predicate, deadline)
    else
      flunk("timed out waiting for instance #{id}")
    end
  end
end
