defmodule Hephaestus.Steps.EndStepTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.End, as: EndStep

  defmodule TestWorkflow do
  end

  describe "execute/3" do
    test "returns completed event" do
      instance = Instance.new(TestWorkflow, %{})
      context = Context.new(%{order_id: 123})

      result = EndStep.execute(instance, nil, context)

      assert {:ok, "completed"} = result
    end

    test "ignores config" do
      instance = Instance.new(TestWorkflow, %{})
      context = Context.new(%{})

      result = EndStep.execute(instance, %{some: "config"}, context)

      assert {:ok, "completed"} = result
    end
  end
end
