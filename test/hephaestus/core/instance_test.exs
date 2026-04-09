defmodule Hephaestus.Core.InstanceTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}

  describe "new/3" do
    test "creates instance with workflow module and context" do
      workflow = MyTestWorkflow
      context = %{order_id: 123}

      instance = Instance.new(workflow, 1, context)

      assert %Instance{
               workflow: MyTestWorkflow,
               status: :pending,
               active_steps: active,
               completed_steps: completed
             } = instance

      assert is_binary(instance.id)
      assert %Context{initial: %{order_id: 123}} = instance.context
      assert MapSet.size(active) == 0
      assert MapSet.size(completed) == 0
      assert instance.execution_history == []
    end

    test "generates unique ids" do
      instance_a = Instance.new(MyTestWorkflow, 1, %{})
      instance_b = Instance.new(MyTestWorkflow, 1, %{})

      refute instance_a.id == instance_b.id
    end

    test "creates instance with default empty context" do
      instance = Instance.new(MyTestWorkflow, 1)

      assert %Context{initial: %{}, steps: %{}} = instance.context
    end
  end

  describe "telemetry fields" do
    test "new/3 creates instance with default telemetry_metadata as empty map" do
      instance = Instance.new(MyTestWorkflow, 1, %{order_id: 1})

      assert Map.get(instance, :telemetry_metadata) == %{}
    end

    test "new/3 creates instance with default telemetry_start_time as nil" do
      instance = Instance.new(MyTestWorkflow, 1, %{})

      assert Map.get(instance, :telemetry_start_time) == nil
    end

    test "telemetry_metadata can be set after creation" do
      instance = Instance.new(MyTestWorkflow, 1, %{})
      updated = Map.put(instance, :telemetry_metadata, %{request_id: "abc-123"})

      assert Map.get(updated, :telemetry_metadata) == %{request_id: "abc-123"}
    end
  end
end
