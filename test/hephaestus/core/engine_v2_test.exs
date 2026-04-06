defmodule Hephaestus.Core.EngineV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Engine, Instance}

  describe "advance/1" do
    test "pending instance becomes running with start module active" do
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      {:ok, advanced} = Engine.advance(instance)

      assert advanced.status == :running
      assert MapSet.member?(advanced.active_steps, Hephaestus.Test.V2.StepA)
    end

    test "start/0 returning {module, config} stores config in step_configs" do
      instance = Instance.new(Hephaestus.Test.V2.ConfigStartWorkflow, %{})

      {:ok, advanced} = Engine.advance(instance)

      assert advanced.step_configs[Hephaestus.Test.V2.ConfigStep] == %{timeout: 5000}
    end
  end

  describe "execute_step/2" do
    test "calls module.execute/3 with config from step_configs" do
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        step_configs: %{Hephaestus.Test.V2.ConfigStep => %{timeout: 5000}}}

      result = Engine.execute_step(instance, Hephaestus.Test.V2.ConfigStep)

      assert {:ok, :done, %{config_received: %{timeout: 5000}}} = result
    end

    test "passes nil config when step has no config" do
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      result = Engine.execute_step(instance, Hephaestus.Test.V2.StepA)

      assert {:ok, :done} = result
    end

    test "raises when module does not implement execute/3" do
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{})

      assert_raise RuntimeError, ~r/must implement execute\/3/, fn ->
        Engine.execute_step(instance, Hephaestus.Test.V2.NotAStep)
      end
    end
  end

  describe "complete_step/4" do
    test "moves step from active to completed and stores context with snake_case key" do
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      completed = Engine.complete_step(instance, Hephaestus.Test.V2.StepA, :done, %{item_count: 3})

      refute MapSet.member?(completed.active_steps, Hephaestus.Test.V2.StepA)
      assert MapSet.member?(completed.completed_steps, Hephaestus.Test.V2.StepA)
      assert completed.context.steps.step_a.item_count == 3
    end

    test "cleans up step_configs after completion" do
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.ConfigStep]),
        step_configs: %{Hephaestus.Test.V2.ConfigStep => %{timeout: 5000}},
        status: :running}

      completed = Engine.complete_step(instance, Hephaestus.Test.V2.ConfigStep, :done, %{})

      refute Map.has_key?(completed.step_configs, Hephaestus.Test.V2.ConfigStep)
    end

    test "uses step_key/0 override for context key" do
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        active_steps: MapSet.new([Hephaestus.Test.V2.StepWithCustomKey]),
        status: :running}

      completed = Engine.complete_step(instance, Hephaestus.Test.V2.StepWithCustomKey, :done, %{data: true})

      assert completed.context.steps.custom_key.data == true
    end
  end

  describe "activate_transitions/3" do
    test "activates next step from transit/2" do
      instance = %{Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.StepB)
    end

    test "activates multiple steps on fan-out" do
      instance = %{Instance.new(Hephaestus.Test.V2.FanOutWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.ParallelA)
      assert MapSet.member?(activated.active_steps, Hephaestus.Test.V2.ParallelB)
    end

    test "fan-in waits for all predecessors before activating join" do
      instance = %{Instance.new(Hephaestus.Test.V2.FanOutWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA, Hephaestus.Test.V2.ParallelA]),
        status: :running}

      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.ParallelA, :done)

      refute MapSet.member?(activated.active_steps, Hephaestus.Test.V2.JoinStep)
    end

    test "stores transition config for activated steps" do
      defmodule TransitionConfigWorkflow do
        use Hephaestus.Workflow

        @impl true
        def start, do: Hephaestus.Test.V2.StepA

        @impl true
        def transit(Hephaestus.Test.V2.StepA, :done), do: {Hephaestus.Test.V2.ConfigStep, %{timeout: 1000}}
        def transit(Hephaestus.Test.V2.ConfigStep, :done), do: Hephaestus.Steps.End
      end

      instance = %{Instance.new(TransitionConfigWorkflow, %{}) |
        completed_steps: MapSet.new([Hephaestus.Test.V2.StepA]),
        status: :running}

      activated = Engine.activate_transitions(instance, Hephaestus.Test.V2.StepA, :done)

      assert activated.step_configs[Hephaestus.Test.V2.ConfigStep] == %{timeout: 1000}
    end
  end
end
