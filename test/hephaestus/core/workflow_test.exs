defmodule Hephaestus.Core.WorkflowTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Step, Workflow}

  describe "struct creation" do
    test "creates workflow with required fields" do
      workflow = %Workflow{
        initial_step: :start,
        steps: [
          %Step{ref: :start, module: MyStep, transitions: %{"done" => :finish}},
          %Step{ref: :finish, module: MyEndStep}
        ]
      }

      assert workflow.initial_step == :start
      assert length(workflow.steps) == 2
    end

    test "raises when initial_step is missing" do
      assert_raise ArgumentError, fn ->
        struct!(Workflow, steps: [])
      end
    end

    test "raises when steps is missing" do
      assert_raise ArgumentError, fn ->
        struct!(Workflow, initial_step: :start)
      end
    end
  end
end
