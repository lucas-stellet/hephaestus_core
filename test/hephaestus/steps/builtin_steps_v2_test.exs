defmodule Hephaestus.Steps.BuiltinStepsV2Test do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.{End, Debug, Wait, WaitForEvent}

  defp dummy_instance do
    %Instance{
      id: "test-123",
      workflow: __MODULE__,
      context: Context.new(%{}),
      step_configs: %{},
      active_steps: MapSet.new(),
      completed_steps: MapSet.new(),
      execution_history: []
    }
  end

  describe "End" do
    test "events/0 returns [:end]" do
      events = End.events()

      assert events == [:end]
    end

    test "execute/3 returns {:ok, :end}" do
      instance = dummy_instance()
      result = End.execute(instance, nil, instance.context)

      assert {:ok, :end} = result
    end
  end

  describe "Debug" do
    test "events/0 returns [:completed]" do
      events = Debug.events()

      assert events == [:completed]
    end

    test "execute/3 returns {:ok, :completed}" do
      instance = dummy_instance()
      result = Debug.execute(instance, nil, instance.context)

      assert {:ok, :completed} = result
    end
  end

  describe "Wait" do
    test "events/0 returns [:timeout]" do
      events = Wait.events()

      assert events == [:timeout]
    end

    test "execute/3 returns {:async}" do
      instance = dummy_instance()
      result = Wait.execute(instance, nil, instance.context)

      assert {:async} = result
    end
  end

  describe "WaitForEvent" do
    test "events/0 returns [:received]" do
      events = WaitForEvent.events()

      assert events == [:received]
    end

    test "execute/3 returns {:async}" do
      instance = dummy_instance()
      result = WaitForEvent.execute(instance, nil, instance.context)

      assert {:async} = result
    end
  end
end
