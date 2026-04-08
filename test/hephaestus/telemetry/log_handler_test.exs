defmodule Hephaestus.Telemetry.LogHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Hephaestus.Telemetry
  alias Hephaestus.Telemetry.LogHandler
  alias Hephaestus.Core.Instance

  setup do
    on_exit(fn ->
      LogHandler.detach()
    end)

    instance = %Instance{
      id: "log-test-001",
      workflow: MyApp.OrderWorkflow,
      telemetry_metadata: %{}
    }

    {:ok, instance: instance}
  end

  describe "attach/1" do
    test "attaches handler successfully" do
      # Act
      result = LogHandler.attach()

      # Assert
      assert result == :ok
    end

    test "returns error when already attached" do
      # Arrange
      LogHandler.attach()

      # Act
      result = LogHandler.attach()

      # Assert
      assert result == {:error, :already_exists}
    end
  end

  describe "detach/0" do
    test "detaches handler successfully" do
      # Arrange
      LogHandler.attach()

      # Act / Assert
      assert LogHandler.detach() == :ok
    end

    test "returns error when not attached" do
      # Act / Assert
      assert LogHandler.detach() == {:error, :not_found}
    end
  end

  describe "workflow events" do
    test "logs workflow start at info level", %{instance: instance} do
      # Arrange
      LogHandler.attach()

      # Act
      log =
        capture_log(fn ->
          Telemetry.workflow_start(instance, %{runner: Runner.Local})
          Process.sleep(10)
        end)

      # Assert
      assert log =~ "Workflow started"
      assert log =~ "log-test-001"
    end

    test "logs workflow exception at error level", %{instance: instance} do
      # Arrange
      LogHandler.attach()

      # Act
      log =
        capture_log(fn ->
          Telemetry.workflow_exception(instance, :error, :timeout, nil, %{
            failed_step: StepA,
            step_count: 1,
            advance_count: 1,
            runner: Runner.Local
          })

          Process.sleep(10)
        end)

      # Assert
      assert log =~ "[error]"
      assert log =~ "Workflow failed"
    end
  end

  describe "step events" do
    test "logs step stop with duration in milliseconds", %{instance: instance} do
      # Arrange
      LogHandler.attach()
      duration = System.convert_time_unit(150, :millisecond, :native)

      # Act
      log =
        capture_log(fn ->
          Telemetry.step_stop(instance, StepA, duration, %{
            step_key: :step_a,
            event: :done,
            has_context_updates: false,
            has_metadata_updates: false,
            transitions_to: [StepB]
          })

          Process.sleep(10)
        end)

      # Assert
      assert log =~ "Step"
      assert log =~ "completed"
      assert log =~ "150ms" or log =~ "150"
    end

    test "logs step async at warning level", %{instance: instance} do
      # Arrange
      LogHandler.attach()

      # Act
      log =
        capture_log(fn ->
          Telemetry.step_async(instance, StepA, 100, %{
            step_key: :step_a,
            instance_status: :waiting
          })

          Process.sleep(10)
        end)

      # Assert
      assert log =~ "[warning]"
      assert log =~ "waiting"
    end
  end

  describe "options" do
    test "respects custom log level override", %{instance: instance} do
      # Arrange
      LogHandler.attach(level: %{Telemetry.workflow_start_event() => :debug})

      # Act
      log =
        capture_log([level: :debug], fn ->
          Telemetry.workflow_start(instance, %{runner: Runner.Local})
          Process.sleep(10)
        end)

      # Assert
      assert log =~ "[debug]"
      assert log =~ "Workflow started"
    end

    test "only handles specified events when :events option given", %{instance: instance} do
      # Arrange
      LogHandler.attach(events: [Telemetry.workflow_start_event()])

      # Act
      log =
        capture_log(fn ->
          Telemetry.workflow_start(instance, %{runner: Runner.Local})

          Telemetry.runner_init(%{
            name: Test,
            runner: Runner.Local,
            storage: Storage.ETS,
            pid: self()
          })

          Process.sleep(10)
        end)

      # Assert
      assert log =~ "Workflow started"
      refute log =~ "runner initialized"
    end
  end
end
