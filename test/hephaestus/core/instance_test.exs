defmodule Hephaestus.Core.InstanceTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}

  describe "new/2" do
    test "creates instance with workflow module and context" do
      workflow = MyTestWorkflow
      context = %{order_id: 123}

      instance = Instance.new(workflow, context)

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
      instance_a = Instance.new(MyTestWorkflow, %{})
      instance_b = Instance.new(MyTestWorkflow, %{})

      refute instance_a.id == instance_b.id
    end

    test "creates instance with default empty context" do
      instance = Instance.new(MyTestWorkflow)

      assert %Context{initial: %{}, steps: %{}} = instance.context
    end
  end

  describe "telemetry fields" do
    test "new/2 creates instance with default telemetry_metadata as empty map" do
      instance = Instance.new(MyTestWorkflow, %{order_id: 1})

      assert Map.get(instance, :telemetry_metadata) == %{}
    end

    test "new/2 creates instance with default telemetry_start_time as nil" do
      instance = Instance.new(MyTestWorkflow, %{})

      assert Map.get(instance, :telemetry_start_time) == nil
    end

    test "telemetry_metadata can be set after creation" do
      instance = Instance.new(MyTestWorkflow, %{})
      updated = Map.put(instance, :telemetry_metadata, %{request_id: "abc-123"})

      assert Map.get(updated, :telemetry_metadata) == %{request_id: "abc-123"}
    end
  end
end
