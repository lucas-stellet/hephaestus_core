defmodule Hephaestus.Steps.WaitTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.Wait

  defmodule TestWorkflow do
  end

  describe "execute/3" do
    test "returns async for valid config" do
      instance = Instance.new(TestWorkflow, %{})
      config = %{duration: 30, unit: :minute}
      context = Context.new(%{})

      result = Wait.execute(instance, config, context)

      assert {:async} = result
    end
  end

  describe "delay_ms/1" do
    test "converts seconds to milliseconds" do
      config = %{duration: 10, unit: :second}

      assert Wait.delay_ms(config) == 10_000
    end

    test "converts minutes to milliseconds" do
      config = %{duration: 5, unit: :minute}

      assert Wait.delay_ms(config) == 300_000
    end

    test "converts hours to milliseconds" do
      config = %{duration: 2, unit: :hour}

      assert Wait.delay_ms(config) == 7_200_000
    end

    test "converts days to milliseconds" do
      config = %{duration: 1, unit: :day}

      assert Wait.delay_ms(config) == 86_400_000
    end
  end
end
