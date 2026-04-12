defmodule Hephaestus.Steps.WaitForEventTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.WaitForEvent

  defmodule TestWorkflow do
  end

  defp new_instance do
    Instance.new(
      TestWorkflow,
      1,
      %{},
      "wait-for-event-test-#{System.unique_integer([:positive])}"
    )
  end

  describe "execute/3" do
    test "returns async" do
      instance = new_instance()
      config = %{event_name: "payment_confirmed"}
      context = Context.new(%{})

      result = WaitForEvent.execute(instance, config, context)

      assert {:async} = result
    end

    test "returns async with timeout config" do
      instance = new_instance()
      config = %{event_name: "payment_confirmed", timeout_ms: 60_000}
      context = Context.new(%{})

      result = WaitForEvent.execute(instance, config, context)

      assert {:async} = result
    end
  end
end
