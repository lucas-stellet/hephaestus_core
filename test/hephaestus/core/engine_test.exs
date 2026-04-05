defmodule Hephaestus.Core.EngineTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Engine, Instance}

  describe "advance/1 - linear workflow" do
    test "executes all steps and completes" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :step_a)
      assert MapSet.member?(instance.completed_steps, :step_b)
      assert MapSet.member?(instance.completed_steps, :finish)
    end

    test "accumulates context from steps" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert %{processed: true} = instance.context.steps[:step_b]
    end

    test "preserves initial context" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{order_id: 123})

      {:ok, instance} = Engine.advance(instance)

      assert instance.context.initial == %{order_id: 123}
    end

    test "builds execution history" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      refs = Enum.map(instance.execution_history, & &1.step_ref)
      assert :step_a in refs
      assert :step_b in refs
      assert :finish in refs
    end
  end

  describe "advance/1 - branching workflow" do
    test "follows true branch" do
      instance = Instance.new(Hephaestus.Test.BranchWorkflow, %{should_approve: true})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :approve)
      refute MapSet.member?(instance.completed_steps, :reject)
    end

    test "follows false branch" do
      instance = Instance.new(Hephaestus.Test.BranchWorkflow, %{should_approve: false})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :reject)
      refute MapSet.member?(instance.completed_steps, :approve)
    end
  end

  describe "advance/1 - fan-out / fan-in" do
    test "activates all fan-out targets" do
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :completed
      assert MapSet.member?(instance.completed_steps, :branch_a)
      assert MapSet.member?(instance.completed_steps, :branch_b)
      assert MapSet.member?(instance.completed_steps, :join)
    end

    test "fan-in step receives context from all predecessors" do
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert %{processed: true} = instance.context.steps[:branch_a]
      assert %{processed: true} = instance.context.steps[:branch_b]
    end

    test "join step only executes after all predecessors complete" do
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      history_refs = Enum.map(instance.execution_history, & &1.step_ref)
      join_idx = Enum.find_index(history_refs, &(&1 == :join))
      branch_a_idx = Enum.find_index(history_refs, &(&1 == :branch_a))
      branch_b_idx = Enum.find_index(history_refs, &(&1 == :branch_b))
      assert join_idx > branch_a_idx
      assert join_idx > branch_b_idx
    end
  end

  describe "advance/1 - async step" do
    test "pauses at async step with waiting status" do
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :waiting
      assert MapSet.member?(instance.active_steps, :wait)
      assert MapSet.member?(instance.completed_steps, :step_a)
    end
  end

  describe "advance/1 - error handling" do
    test "returns error when step fails" do
      defmodule FailWorkflow do
        use Hephaestus.Workflow
        alias Hephaestus.Core.Step

        @impl true
        def definition do
          %Hephaestus.Core.Workflow{
            initial_step: :start,
            steps: [
              %Step{ref: :start, module: Hephaestus.Test.FailStep, transitions: %{"done" => :finish}},
              %Step{ref: :finish, module: Hephaestus.Steps.End}
            ]
          }
        end
      end

      instance = Instance.new(FailWorkflow, %{})

      assert {:error, :something_went_wrong} = Engine.advance(instance)
    end
  end

  describe "resume/2" do
    test "resumes waiting instance and continues execution" do
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
      {:ok, paused} = Engine.advance(instance)
      assert paused.status == :waiting

      resumed = Engine.resume(paused, "timeout")
      {:ok, completed} = Engine.advance(resumed)

      assert completed.status == :completed
      assert MapSet.member?(completed.completed_steps, :step_b)
    end
  end

  describe "complete_step/4" do
    test "marks step as completed and updates context" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:active_steps, MapSet.new([:step_a]))
        |> Map.put(:status, :running)

      instance = Engine.complete_step(instance, :step_a, "done", %{result: "ok"})

      assert MapSet.member?(instance.completed_steps, :step_a)
      refute MapSet.member?(instance.active_steps, :step_a)
      assert %{result: "ok"} = instance.context.steps[:step_a]
    end

    test "adds execution entry to history" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:active_steps, MapSet.new([:step_a]))
        |> Map.put(:status, :running)

      instance = Engine.complete_step(instance, :step_a, "done", %{})

      assert [%{step_ref: :step_a, event: "done"} | _] = instance.execution_history
    end
  end

  describe "status transitions" do
    test "pending -> running on first advance" do
      instance = Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
      assert instance.status == :pending

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :waiting
      assert MapSet.member?(instance.completed_steps, :step_a)
    end
  end
end
