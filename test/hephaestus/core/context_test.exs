defmodule Hephaestus.Core.ContextTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.Context

  describe "new/1" do
    test "creates context with initial data" do
      initial = %{order_id: 123, items: ["a", "b"]}

      context = Context.new(initial)

      assert %Context{initial: %{order_id: 123, items: ["a", "b"]}, steps: %{}} = context
    end

    test "creates context with empty initial data" do
      context = Context.new(%{})

      assert %Context{initial: %{}, steps: %{}} = context
    end
  end

  describe "put_step_result/3" do
    test "adds step result namespaced by step ref" do
      context = Context.new(%{order_id: 123})

      context = Context.put_step_result(context, :validate, %{valid: true})

      assert %{validate: %{valid: true}} = context.steps
    end

    test "preserves existing step results when adding new one" do
      context =
        Context.new(%{})
        |> Context.put_step_result(:step_a, %{result: "a"})

      context = Context.put_step_result(context, :step_b, %{result: "b"})

      assert %{step_a: %{result: "a"}, step_b: %{result: "b"}} = context.steps
    end

    test "overwrites step result if same ref is used" do
      context =
        Context.new(%{})
        |> Context.put_step_result(:step_a, %{result: "old"})

      context = Context.put_step_result(context, :step_a, %{result: "new"})

      assert %{step_a: %{result: "new"}} = context.steps
    end

    test "does not modify initial data" do
      context = Context.new(%{order_id: 123})

      context = Context.put_step_result(context, :validate, %{valid: true})

      assert %{order_id: 123} = context.initial
    end
  end
end
