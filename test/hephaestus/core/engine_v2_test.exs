defmodule Hephaestus.Test.V2.EngineBranchWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.BranchStep

  @impl true
  def transit(Hephaestus.Test.V2.BranchStep, :approved), do: Hephaestus.Test.V2.ApproveStep
  def transit(Hephaestus.Test.V2.BranchStep, :rejected), do: Hephaestus.Test.V2.RejectStep
  def transit(Hephaestus.Test.V2.ApproveStep, :done), do: Hephaestus.Steps.End
  def transit(Hephaestus.Test.V2.RejectStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.EngineDynamicWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  @targets [Hephaestus.Test.V2.StepB, Hephaestus.Test.V2.StepC]
  def transit(Hephaestus.Test.V2.StepA, :done, ctx) do
    if ctx.initial.use_b do
      Hephaestus.Test.V2.StepB
    else
      Hephaestus.Test.V2.StepC
    end
  end

  @impl true
  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
  def transit(Hephaestus.Test.V2.StepC, :done), do: Hephaestus.Steps.End
end

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

  describe "full linear flow without OTP" do
    test "advances through A -> B -> End entirely in pure functions" do
      instance = Instance.new(Hephaestus.Test.V2.LinearWorkflow, %{data: "test"})

      {:ok, inst} = Engine.advance(instance)
      assert inst.status == :running
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepA)

      {:ok, event} = Engine.execute_step(inst, Hephaestus.Test.V2.StepA)
      assert event == :done

      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepA, :done, %{})
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepA, :done)
      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepB)

      {:ok, event, ctx} = Engine.execute_step(inst, Hephaestus.Test.V2.StepB)
      assert event == :done

      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepB, :done, ctx)
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepB, :done)
      assert MapSet.member?(inst.active_steps, Hephaestus.Steps.End)

      {:ok, event} = Engine.execute_step(inst, Hephaestus.Steps.End)
      assert event == :end

      inst = Engine.complete_step(inst, Hephaestus.Steps.End, :end, %{})
      inst = Engine.check_completion(inst)

      assert inst.status == :completed
    end
  end

  describe "full branch flow without OTP" do
    test "takes approved branch" do
      instance = Instance.new(Hephaestus.Test.V2.EngineBranchWorkflow, %{approved: true})

      {:ok, inst} = Engine.advance(instance)
      {:ok, event} = Engine.execute_step(inst, Hephaestus.Test.V2.BranchStep)

      assert event == :approved

      inst = Engine.complete_step(inst, Hephaestus.Test.V2.BranchStep, :approved, %{})
      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.BranchStep, :approved)

      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.ApproveStep)
      refute MapSet.member?(inst.active_steps, Hephaestus.Test.V2.RejectStep)
    end
  end

  describe "dynamic transit/3 flow" do
    test "resolves transit/3 using context" do
      instance = Instance.new(Hephaestus.Test.V2.EngineDynamicWorkflow, %{use_b: true})

      {:ok, inst} = Engine.advance(instance)
      {:ok, :done} = Engine.execute_step(inst, Hephaestus.Test.V2.StepA)
      inst = Engine.complete_step(inst, Hephaestus.Test.V2.StepA, :done, %{})

      inst = Engine.activate_transitions(inst, Hephaestus.Test.V2.StepA, :done)

      assert MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepB)
      refute MapSet.member?(inst.active_steps, Hephaestus.Test.V2.StepC)
    end
  end
end
