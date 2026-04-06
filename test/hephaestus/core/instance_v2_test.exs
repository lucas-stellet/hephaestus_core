defmodule Hephaestus.Core.InstanceV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Instance

  describe "step_configs field" do
    test "new instance has empty step_configs" do
      instance = Instance.new(SomeWorkflow, %{})

      assert instance.step_configs == %{}
    end

    test "step_configs can store module => config mapping" do
      instance = Instance.new(SomeWorkflow, %{})

      updated = %{instance | step_configs: Map.put(instance.step_configs, MyStep, %{timeout: 5000})}

      assert updated.step_configs == %{MyStep => %{timeout: 5000}}
    end

    test "step_configs can be cleared per module" do
      instance = Instance.new(SomeWorkflow, %{})
      with_config = %{instance | step_configs: %{MyStep => %{timeout: 5000}, OtherStep => %{retries: 3}}}

      cleared = %{with_config | step_configs: Map.delete(with_config.step_configs, MyStep)}

      assert cleared.step_configs == %{OtherStep => %{retries: 3}}
    end
  end

  describe "types reflect module identity" do
    test "active_steps stores modules" do
      instance = Instance.new(SomeWorkflow, %{})

      updated = %{instance | active_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      assert MapSet.member?(updated.active_steps, MyApp.Steps.ValidateOrder)
    end

    test "completed_steps stores modules" do
      instance = Instance.new(SomeWorkflow, %{})

      updated = %{instance | completed_steps: MapSet.new([MyApp.Steps.ValidateOrder])}

      assert MapSet.member?(updated.completed_steps, MyApp.Steps.ValidateOrder)
    end

    test "current_step stores module" do
      instance = Instance.new(SomeWorkflow, %{})

      updated = %{instance | current_step: MyApp.Steps.ValidateOrder}

      assert updated.current_step == MyApp.Steps.ValidateOrder
    end
  end
end
