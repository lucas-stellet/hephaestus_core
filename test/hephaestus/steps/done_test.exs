defmodule Hephaestus.Steps.DoneTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}
  alias Hephaestus.Steps.Done

  defmodule TestWorkflow do
  end

  defp new_instance do
    Instance.new(TestWorkflow, 1, %{}, "done-test-#{System.unique_integer([:positive])}")
  end

  describe "execute/3" do
    test "returns done event" do
      instance = new_instance()
      context = Context.new(%{order_id: 123})

      result = Done.execute(instance, nil, context)

      assert {:ok, :done} = result
    end

    test "ignores config" do
      instance = new_instance()
      context = Context.new(%{})

      result = Done.execute(instance, %{some: "config"}, context)

      assert {:ok, :done} = result
    end
  end
end
