defmodule Hephaestus.Steps.DoneTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.Done

  defmodule TestWorkflow do
  end

  describe "execute/3" do
    test "returns done event" do
      instance = Instance.new(TestWorkflow, 1, %{})
      context = Context.new(%{order_id: 123})

      result = Done.execute(instance, nil, context)

      assert {:ok, :done} = result
    end

    test "ignores config" do
      instance = Instance.new(TestWorkflow, 1, %{})
      context = Context.new(%{})

      result = Done.execute(instance, %{some: "config"}, context)

      assert {:ok, :done} = result
    end
  end
end
