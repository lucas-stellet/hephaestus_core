defmodule Hephaestus.Core.InstanceV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Instance

  describe "step_configs field" do
    test "new instance has empty step_configs" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::step-configs-empty")

      assert instance.step_configs == %{}
    end

    test "step_configs can store module => config mapping" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::step-configs-store")

      updated = %{
        instance
        | step_configs: Map.put(instance.step_configs, MyStep, %{timeout: 5000})
      }

      assert updated.step_configs == %{MyStep => %{timeout: 5000}}
    end

    test "step_configs can be cleared per module" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::step-configs-clear")

      with_config = %{
        instance
        | step_configs: %{MyStep => %{timeout: 5000}, OtherStep => %{retries: 3}}
      }

      cleared = %{with_config | step_configs: Map.delete(with_config.step_configs, MyStep)}

      assert cleared.step_configs == %{OtherStep => %{retries: 3}}
    end
  end

  describe "workflow_version field" do
    test "new/4 creates instance with explicit version" do
      # Arrange
      workflow = Hephaestus.Test.V2.LinearWorkflow
      version = 2

      # Act
      instance = Instance.new(workflow, version, %{order_id: 1}, "test::workflow-version")

      # Assert
      assert instance.workflow == Hephaestus.Test.V2.LinearWorkflow
      assert instance.workflow_version == 2
      assert instance.context.initial == %{order_id: 1}
      assert instance.status == :pending
      assert instance.id == "test::workflow-version"
    end

    test "new/4 with empty context" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::default-context")

      assert instance.workflow_version == 1
      assert instance.context.initial == %{}
    end

    test "workflow_version defaults to 1 in bare struct" do
      # Arrange & Act
      instance = %Instance{id: "test-id", workflow: SomeWorkflow}

      # Assert
      assert instance.workflow_version == 1
    end

    test "new/4 rejects non-positive version" do
      # Assert
      assert_raise FunctionClauseError, fn ->
        Instance.new(SomeWorkflow, 0, %{}, "test::invalid-version-zero")
      end

      assert_raise FunctionClauseError, fn ->
        Instance.new(SomeWorkflow, -1, %{}, "test::invalid-version-negative")
      end
    end
  end

  describe "types reflect module identity" do
    test "active_steps stores modules" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::active-steps")

      updated = %{instance | active_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      assert MapSet.member?(updated.active_steps, MyApp.Steps.ValidateOrder)
    end

    test "completed_steps stores modules" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::completed-steps")

      updated = %{instance | completed_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      assert MapSet.member?(updated.completed_steps, MyApp.Steps.ValidateOrder)
    end

    test "current_step stores module" do
      instance = Instance.new(SomeWorkflow, 1, %{}, "test::current-step")

      updated = %{instance | current_step: MyApp.Steps.ValidateOrder}

      assert updated.current_step == MyApp.Steps.ValidateOrder
    end
  end
end
