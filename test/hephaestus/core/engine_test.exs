defmodule Hephaestus.Core.EngineTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Engine, ExecutionEntry, Instance}

  describe "advance/1" do
    test "pending -> running with initial step active and does not execute" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :running
      assert instance.active_steps == MapSet.new([:step_a])
      assert instance.completed_steps == MapSet.new()
      assert instance.execution_history == []
      assert instance.context.steps == %{}
    end

    test "running with active steps returns immediately without changes" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:active_steps, MapSet.new([:step_b]))
        |> Map.put(:completed_steps, MapSet.new([:step_a]))

      {:ok, advanced} = Engine.advance(instance)

      assert advanced == instance
    end

    test "running with no active steps completes instance" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:active_steps, MapSet.new())
        |> Map.put(:completed_steps, MapSet.new([:step_a, :step_b, :finish]))

      {:ok, instance} = Engine.advance(instance)

      assert instance.status == :completed
      assert instance.active_steps == MapSet.new()
    end

    test "waiting returns unchanged" do
      instance =
        Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
        |> Map.put(:status, :waiting)
        |> Map.put(:current_step, :wait)
        |> Map.put(:active_steps, MapSet.new([:wait]))

      {:ok, advanced} = Engine.advance(instance)

      assert advanced == instance
    end
  end

  describe "execute_step/2" do
    test "dispatches through step module and returns step result" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{should_approve: true})
      step_def = instance.workflow.__step__(:step_b)

      assert {:ok, "done", %{processed: true}} = Engine.execute_step(instance, step_def)
    end
  end

  describe "complete_step/4" do
    test "marks step as completed and updates context without creating execution history" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:active_steps, MapSet.new([:step_a]))

      instance = Engine.complete_step(instance, :step_a, "done", %{result: "ok"})

      assert MapSet.member?(instance.completed_steps, :step_a)
      refute MapSet.member?(instance.active_steps, :step_a)
      assert %{result: "ok"} = instance.context.steps[:step_a]
      assert instance.execution_history == []
    end
  end

  describe "activate_transitions/3" do
    test "activates single target when predecessors are satisfied" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:completed_steps, MapSet.new([:step_a]))

      instance = Engine.activate_transitions(instance, :step_a, "done")

      assert instance.active_steps == MapSet.new([:step_b])
    end

    test "supports fan-out targets" do
      instance =
        Instance.new(Hephaestus.Test.ParallelWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:completed_steps, MapSet.new([:start]))

      instance = Engine.activate_transitions(instance, :start, "done")

      assert instance.active_steps == MapSet.new([:branch_a, :branch_b])
    end

    test "respects fan-in predecessors before activating join step" do
      instance =
        Instance.new(Hephaestus.Test.ParallelWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:completed_steps, MapSet.new([:start, :branch_a]))

      instance = Engine.activate_transitions(instance, :branch_a, "done")

      refute MapSet.member?(instance.active_steps, :join)

      instance =
        instance
        |> Map.put(:completed_steps, MapSet.new([:start, :branch_a, :branch_b]))
        |> Engine.activate_transitions(:branch_b, "done")

      assert MapSet.member?(instance.active_steps, :join)
    end
  end

  describe "check_completion/1" do
    test "completes running instance when no active steps remain" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:active_steps, MapSet.new())

      instance = Engine.check_completion(instance)

      assert instance.status == :completed
    end

    test "keeps status when active steps remain" do
      instance =
        Instance.new(Hephaestus.Test.LinearWorkflow, %{})
        |> Map.put(:status, :running)
        |> Map.put(:active_steps, MapSet.new([:step_b]))

      instance = Engine.check_completion(instance)

      assert instance.status == :running
    end
  end

  describe "resume_step/3" do
    test "removes the explicit active step, marks it completed, and activates transitions" do
      instance =
        Instance.new(Hephaestus.Test.AsyncWorkflow, %{})
        |> Map.put(:status, :waiting)
        |> Map.put(:current_step, :wait)
        |> Map.put(:active_steps, MapSet.new([:wait]))
        |> Map.put(:completed_steps, MapSet.new([:step_a]))

      resumed = Engine.resume_step(instance, :wait, "timeout")

      assert resumed.status == :running
      assert resumed.current_step == nil
      refute MapSet.member?(resumed.active_steps, :wait)
      assert MapSet.member?(resumed.completed_steps, :wait)
      assert MapSet.member?(resumed.active_steps, :step_b)
    end

    test "uses the provided step ref instead of current_step" do
      instance =
        Instance.new(Hephaestus.Test.ParallelWorkflow, %{})
        |> Map.put(:status, :waiting)
        |> Map.put(:current_step, :branch_a)
        |> Map.put(:active_steps, MapSet.new([:branch_b]))
        |> Map.put(:completed_steps, MapSet.new([:start, :branch_a]))

      resumed = Engine.resume_step(instance, :branch_b, "done")

      assert resumed.status == :running
      refute MapSet.member?(resumed.active_steps, :branch_b)
      assert MapSet.member?(resumed.completed_steps, :branch_b)
      assert MapSet.member?(resumed.active_steps, :join)
    end
  end

  describe "manual engine flow" do
    test "runs a linear workflow by chaining public primitives" do
      instance = Instance.new(Hephaestus.Test.LinearWorkflow, %{order_id: 123})

      {:ok, instance} = Engine.advance(instance)
      assert instance.status == :running
      assert instance.active_steps == MapSet.new([:step_a])

      instance = run_step(instance, :step_a, ~U[2026-04-04 22:20:00Z])
      assert instance.active_steps == MapSet.new([:step_b])

      instance = run_step(instance, :step_b, ~U[2026-04-04 22:21:00Z])
      assert instance.active_steps == MapSet.new([:finish])

      instance = run_step(instance, :finish, ~U[2026-04-04 22:22:00Z])
      instance = Engine.check_completion(instance)

      assert instance.status == :completed
      assert instance.context.initial == %{order_id: 123}
      assert %{processed: true} = instance.context.steps[:step_b]
      assert MapSet.subset?(MapSet.new([:step_a, :step_b, :finish]), instance.completed_steps)
      assert Enum.map(instance.execution_history, & &1.step_ref) == [:step_a, :step_b, :finish]
    end

    test "handles fan-out and fan-in by processing active steps explicitly" do
      instance = Instance.new(Hephaestus.Test.ParallelWorkflow, %{})

      {:ok, instance} = Engine.advance(instance)
      instance = run_step(instance, :start, ~U[2026-04-04 22:30:00Z])

      assert instance.active_steps == MapSet.new([:branch_a, :branch_b])

      instance = run_step(instance, :branch_a, ~U[2026-04-04 22:31:00Z])
      refute MapSet.member?(instance.active_steps, :join)

      instance = run_step(instance, :branch_b, ~U[2026-04-04 22:32:00Z])
      assert instance.active_steps == MapSet.new([:join])

      instance = run_step(instance, :join, ~U[2026-04-04 22:33:00Z])
      instance = run_step(instance, :finish, ~U[2026-04-04 22:34:00Z])
      instance = Engine.check_completion(instance)

      assert instance.status == :completed
      assert %{processed: true} = instance.context.steps[:branch_a]
      assert %{processed: true} = instance.context.steps[:branch_b]
      assert Enum.map(instance.execution_history, & &1.step_ref) == [
               :start,
               :branch_a,
               :branch_b,
               :join,
               :finish
             ]
    end
  end

  describe "legacy behavior removed" do
    test "advance does not execute failing steps automatically" do
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

      assert {:ok, %{status: :running, active_steps: active_steps}} = Engine.advance(instance)
      assert active_steps == MapSet.new([:start])
    end
  end

  defp run_step(instance, step_ref, timestamp) do
    step_def = instance.workflow.__step__(step_ref)

    {event, context_updates} =
      case Engine.execute_step(instance, step_def) do
        {:ok, event} -> {event, %{}}
        {:ok, event, context_updates} -> {event, context_updates}
      end

    instance
    |> Engine.complete_step(step_ref, event, context_updates)
    |> append_execution_entry(step_ref, event, timestamp, context_updates)
    |> Engine.activate_transitions(step_ref, event)
  end

  defp append_execution_entry(instance, step_ref, event, timestamp, context_updates) do
    entry = %ExecutionEntry{
      step_ref: step_ref,
      event: event,
      timestamp: timestamp,
      context_updates: context_updates
    }

    %{instance | execution_history: instance.execution_history ++ [entry]}
  end
end
