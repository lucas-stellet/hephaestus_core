defmodule Hephaestus.Core.InstanceTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}

  describe "new/4" do
    test "creates instance with explicit ID" do
      workflow = MyTestWorkflow
      id = "orderid::abc123"

      instance = Instance.new(workflow, 1, %{order_id: 123}, id)

      assert %Instance{
               id: "orderid::abc123",
               workflow: MyTestWorkflow,
               workflow_version: 1,
               status: :pending
             } = instance

      assert %Context{initial: %{order_id: 123}} = instance.context
    end

    test "preserves the exact ID provided" do
      id = "blueprintid::550e8400-e29b-41d4-a716-446655440000"

      instance = Instance.new(MyTestWorkflow, 1, %{}, id)

      assert instance.id == "blueprintid::550e8400-e29b-41d4-a716-446655440000"
    end

    test "initializes with empty active and completed steps" do
      instance = Instance.new(MyTestWorkflow, 1, %{}, "test::init")

      assert MapSet.size(instance.active_steps) == 0
      assert MapSet.size(instance.completed_steps) == 0
      assert instance.execution_history == []
    end

    test "sets workflow version" do
      instance = Instance.new(MyTestWorkflow, 3, %{}, "test::v3")

      assert instance.workflow_version == 3
    end

    test "initializes telemetry fields with defaults" do
      instance = Instance.new(MyTestWorkflow, 1, %{}, "test::telem")

      assert instance.telemetry_metadata == %{}
      assert instance.telemetry_start_time == nil
    end
  end

  describe "new/4 guards" do
    test "rejects non-binary ID" do
      assert_raise FunctionClauseError, fn ->
        apply(Instance, :new, [MyTestWorkflow, 1, %{}, 123])
      end
    end

    test "rejects non-atom workflow" do
      assert_raise FunctionClauseError, fn ->
        apply(Instance, :new, ["NotAModule", 1, %{}, "test::guard"])
      end
    end

    test "rejects zero version" do
      assert_raise FunctionClauseError, fn ->
        apply(Instance, :new, [MyTestWorkflow, 0, %{}, "test::guard"])
      end
    end
  end
end
