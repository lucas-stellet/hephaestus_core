defmodule Hephaestus.Core.ExecutionEntryTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.ExecutionEntry

  describe "struct creation" do
    test "creates entry with required fields" do
      now = DateTime.utc_now()

      entry = %ExecutionEntry{step_ref: :validate, event: "valid", timestamp: now}

      assert entry.step_ref == :validate
      assert entry.event == "valid"
      assert entry.timestamp == now
      assert entry.context_updates == nil
    end

    test "creates entry with context_updates" do
      entry = %ExecutionEntry{
        step_ref: :validate,
        event: "valid",
        timestamp: DateTime.utc_now(),
        context_updates: %{email_valid: true}
      }

      assert entry.context_updates == %{email_valid: true}
    end

    test "raises when step_ref is missing" do
      assert_raise ArgumentError, fn ->
        struct!(ExecutionEntry, event: "valid", timestamp: DateTime.utc_now())
      end
    end
  end
end
