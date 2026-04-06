defmodule Hephaestus.Steps.DebugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Hephaestus.Core.{Context, ExecutionEntry, Instance}
  alias Hephaestus.Steps.Debug

  defmodule TestWorkflow do
  end

  describe "execute/3" do
    test "returns completed atom event" do
      instance = Instance.new(TestWorkflow, %{order_id: 123})
      context = Context.new(%{order_id: 123})

      result =
        capture_log(fn ->
          assert {:ok, :completed} = Debug.execute(instance, nil, context)
        end)

      assert is_binary(result)
    end

    test "logs context initial data" do
      instance = Instance.new(TestWorkflow, %{order_id: 123})
      context = Context.new(%{order_id: 123})

      log =
        capture_log(fn ->
          Debug.execute(instance, nil, context)
        end)

      assert log =~ "order_id"
      assert log =~ "123"
    end

    test "logs step results from context" do
      instance = Instance.new(TestWorkflow, %{})

      context =
        Context.new(%{})
        |> Context.put_step_result(:validate, %{valid: true})

      log =
        capture_log(fn ->
          Debug.execute(instance, nil, context)
        end)

      assert log =~ "validate"
      assert log =~ "valid"
    end

    test "logs execution history" do
      entry = %ExecutionEntry{
        step_ref: :validate,
        event: :valid,
        timestamp: ~U[2026-01-01 00:00:00Z]
      }

      instance = %{Instance.new(TestWorkflow, %{}) | execution_history: [entry]}
      context = Context.new(%{})

      log =
        capture_log(fn ->
          Debug.execute(instance, nil, context)
        end)

      assert log =~ "validate"
      assert log =~ "valid"
    end
  end
end
