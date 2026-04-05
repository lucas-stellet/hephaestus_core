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
end
