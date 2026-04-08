defmodule Hephaestus.TelemetryTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Instance
  alias Hephaestus.Runtime.Runner.Local
  alias Hephaestus.Runtime.Storage.ETS
  alias Hephaestus.Telemetry

  defmodule Handler do
    def handle(event, measurements, metadata, test_pid) do
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end
  end

  setup do
    handler_id = "test-#{inspect(self())}"

    :telemetry.attach_many(
      handler_id,
      Telemetry.events(),
      &Handler.handle/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    instance = %Instance{
      id: "test-uuid-001",
      workflow: MyTestWorkflow,
      telemetry_metadata: %{request_id: "req-123"},
      telemetry_start_time: System.monotonic_time()
    }

    {:ok, instance: instance}
  end

  describe "events/0" do
    test "returns all 11 event names" do
      events = Telemetry.events()

      assert length(events) == 11
      assert [:hephaestus, :workflow, :start] in events
      assert [:hephaestus, :step, :stop] in events
      assert [:hephaestus, :engine, :advance] in events
    end
  end

  describe "workflow_start/2" do
    test "emits workflow start event with system_time and instance metadata", %{instance: instance} do
      Telemetry.workflow_start(instance, %{initial_step: StepA, runner: Local})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.instance_id == "test-uuid-001"
      assert metadata.workflow == MyTestWorkflow
      assert metadata.initial_step == StepA
      assert metadata.runner == Local
    end

    test "merges telemetry_metadata from instance", %{instance: instance} do
      Telemetry.workflow_start(instance, %{runner: Local})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :start], _measurements, metadata}
      assert metadata.request_id == "req-123"
    end

    test "hephaestus fields cannot be overridden by telemetry_metadata" do
      instance = %Instance{
        id: "real-id",
        workflow: MyTestWorkflow,
        telemetry_metadata: %{instance_id: "fake-id", workflow: FakeModule}
      }

      Telemetry.workflow_start(instance, %{runner: Local})

      assert_receive {:telemetry_event, _, _, metadata}
      assert metadata.instance_id == "real-id"
      assert metadata.workflow == MyTestWorkflow
    end
  end

  describe "workflow_stop/2" do
    test "emits workflow stop with duration and counters", %{instance: instance} do
      Process.sleep(1)

      Telemetry.workflow_stop(instance, %{
        step_count: 3,
        advance_count: 4,
        completed_steps: [:a, :b, :c],
        runner: Local
      })

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :stop], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert measurements.step_count == 3
      assert measurements.advance_count == 4
      assert metadata.status == :completed
    end

    test "emits duration nil when telemetry_start_time is nil" do
      instance = %Instance{id: "no-start", workflow: MyTestWorkflow, telemetry_start_time: nil}

      Telemetry.workflow_stop(instance, %{step_count: 0, advance_count: 0, runner: Local})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :stop], measurements, _metadata}
      assert measurements.duration == nil
    end

    test "emits duration nil when telemetry_start_time is in the future" do
      instance = %Instance{
        id: "future-start",
        workflow: MyTestWorkflow,
        telemetry_start_time: System.monotonic_time() + System.convert_time_unit(1, :second, :native)
      }

      Telemetry.workflow_stop(instance, %{step_count: 0, advance_count: 0, runner: Local})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :stop], measurements, _metadata}
      assert measurements.duration == nil
    end
  end

  describe "workflow_exception/5" do
    test "emits exception with kind, reason, stacktrace", %{instance: instance} do
      Telemetry.workflow_exception(instance, :error, :step_failed, nil, %{
        failed_step: StepB,
        step_count: 2,
        advance_count: 3,
        runner: Local
      })

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :exception], measurements, metadata}
      assert is_integer(measurements.duration) or measurements.duration == nil
      assert metadata.kind == :error
      assert metadata.reason == :step_failed
      assert metadata.failed_step == StepB
      assert metadata.status == :failed
    end
  end

  describe "step_start/3" do
    test "emits step start with system_time and step metadata", %{instance: instance} do
      Telemetry.step_start(instance, StepA, %{
        step_key: :step_a,
        concurrent: false,
        active_steps_count: 1
      })

      assert_receive {:telemetry_event, [:hephaestus, :step, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.step == StepA
      assert metadata.step_key == :step_a
      assert metadata.concurrent == false
    end
  end

  describe "step_stop/4" do
    test "emits step stop with duration and event", %{instance: instance} do
      duration = System.convert_time_unit(5, :millisecond, :native)

      Telemetry.step_stop(instance, StepA, duration, %{
        step_key: :step_a,
        event: :completed,
        has_context_updates: true,
        has_metadata_updates: false,
        transitions_to: [StepB, StepC]
      })

      assert_receive {:telemetry_event, [:hephaestus, :step, :stop], measurements, metadata}
      assert measurements.duration == duration
      assert metadata.event == :completed
      assert metadata.transitions_to == [StepB, StepC]
    end
  end

  describe "step_exception/7" do
    test "emits step exception with error details", %{instance: instance} do
      Telemetry.step_exception(instance, StepA, 1000, :error, :timeout, nil, %{step_key: :step_a})

      assert_receive {:telemetry_event, [:hephaestus, :step, :exception], measurements, metadata}
      assert measurements.duration == 1000
      assert metadata.kind == :error
      assert metadata.reason == :timeout
      assert metadata.step == StepA
    end
  end

  describe "step_async/4" do
    test "emits async event with duration", %{instance: instance} do
      Telemetry.step_async(instance, StepA, 500, %{step_key: :step_a, instance_status: :waiting})

      assert_receive {:telemetry_event, [:hephaestus, :step, :async], measurements, metadata}
      assert measurements.duration == 500
      assert metadata.instance_status == :waiting
    end
  end

  describe "step_resume/3" do
    test "emits resume with wait_duration and source", %{instance: instance} do
      Telemetry.step_resume(instance, StepA, %{
        step_key: :step_a,
        resume_event: :approved,
        source: :external,
        wait_duration: 5_000_000
      })

      assert_receive {:telemetry_event, [:hephaestus, :step, :resume], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert measurements.wait_duration == 5_000_000
      assert metadata.resume_event == :approved
      assert metadata.source == :external
    end
  end

  describe "workflow_transition/5" do
    test "emits transition with targets and fan_out flag", %{instance: instance} do
      Telemetry.workflow_transition(instance, StepA, :done, [StepB, StepC], %{})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :transition], measurements, metadata}
      assert measurements.targets_count == 2
      assert metadata.from_step == StepA
      assert metadata.event == :done
      assert metadata.targets == [StepB, StepC]
      assert metadata.fan_out == true
    end

    test "fan_out is false for single target", %{instance: instance} do
      Telemetry.workflow_transition(instance, StepA, :done, [StepB], %{})

      assert_receive {:telemetry_event, [:hephaestus, :workflow, :transition], _measurements, metadata}
      assert metadata.fan_out == false
    end
  end

  describe "engine_advance/3" do
    test "emits advance with duration and counters", %{instance: instance} do
      Telemetry.engine_advance(instance, 1500, %{
        active_steps_count: 2,
        completed_in_advance: 1,
        status_before: :running,
        status_after: :running,
        iteration: 3
      })

      assert_receive {:telemetry_event, [:hephaestus, :engine, :advance], measurements, metadata}
      assert measurements.duration == 1500
      assert measurements.active_steps_count == 2
      assert metadata.iteration == 3
      assert metadata.status_before == :running
    end
  end

  describe "runner_init/1" do
    test "emits runner init with system_time and config" do
      Telemetry.runner_init(%{
        name: MyApp.Hephaestus,
        runner: Local,
        storage: ETS,
        pid: self()
      })

      assert_receive {:telemetry_event, [:hephaestus, :runner, :init], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.name == MyApp.Hephaestus
      assert metadata.runner == Local
    end
  end
end
