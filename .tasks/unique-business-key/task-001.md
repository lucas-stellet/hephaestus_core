# Task 001: Create `Hephaestus.Workflow.Unique` struct with validations

**Wave**: 0 | **Effort**: S
**Depends on**: none
**Blocks**: task-004, task-005, task-006, task-007

## Objective

Create the `Hephaestus.Workflow.Unique` struct that holds business key configuration for workflows. Includes `new!/1` constructor with compile-time validations.

## Files

**Create:** `test/hephaestus/core/workflow/unique_test.exs` — validation tests
**Create:** `lib/hephaestus/core/workflow/unique.ex` — the Unique struct module

## TDD Execution Order

### Phase 1: RED — Write all tests first

Create the test file with all skeletons. Create a minimal module stub (`defmodule Hephaestus.Workflow.Unique do end`) so the test file compiles but all tests fail.

### Phase 2: GREEN — Implement to make tests pass

The struct has two fields:
- `key` (required, string) — business key prefix. Format: `[a-z0-9]+` only. No hyphens, underscores, uppercase.
- `scope` (optional, atom, default `:workflow`) — one of `:workflow`, `:version`, `:global`, `:none`

Implement `new!/1` that accepts a keyword list, creates the struct via `struct!/2`, and validates:
- `key` is a string matching `~r/^[a-z0-9]+$/`
- `key` is not a non-string type (raise "unique key must be a string, got: ...")
- `scope` is one of the valid values
- Missing `key` triggers the standard `struct!` error

All validations raise `ArgumentError` with descriptive messages. Include `@type t`, `@type scope`, `@enforce_keys [:key]`.

### Phase 3: REFACTOR — Clean up if needed

## Tests

**Test file:** `test/hephaestus/core/workflow/unique_test.exs`

```elixir
defmodule Hephaestus.Core.Workflow.UniqueTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Workflow.Unique

  describe "new!/1 happy path" do
    test "creates struct with key and default scope" do
      # Arrange
      opts = [key: "blueprintid"]

      # Act
      unique = Unique.new!(opts)

      # Assert
      assert %Unique{key: "blueprintid", scope: :workflow} = unique
    end

    test "creates struct with explicit scope" do
      # Arrange
      opts = [key: "orderid", scope: :global]

      # Act
      unique = Unique.new!(opts)

      # Assert
      assert %Unique{key: "orderid", scope: :global} = unique
    end
  end

  describe "new!/1 valid scopes" do
    test "accepts scope :workflow" do
      # Arrange / Act / Assert
      assert %Unique{scope: :workflow} = Unique.new!(key: "k", scope: :workflow)
    end

    test "accepts scope :version" do
      # Arrange / Act / Assert
      assert %Unique{scope: :version} = Unique.new!(key: "k", scope: :version)
    end

    test "accepts scope :global" do
      # Arrange / Act / Assert
      assert %Unique{scope: :global} = Unique.new!(key: "k", scope: :global)
    end

    test "accepts scope :none" do
      # Arrange / Act / Assert
      assert %Unique{scope: :none} = Unique.new!(key: "k", scope: :none)
    end
  end

  describe "new!/1 key validation" do
    test "rejects uppercase letters in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "Blueprint") end
    end

    test "rejects hyphens in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "blueprint-id") end
    end

    test "rejects underscores in key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "blueprint_id") end
    end

    test "rejects non-string key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must be a string/,
                   fn -> Unique.new!(key: 123) end
    end

    test "rejects atom key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must be a string/,
                   fn -> Unique.new!(key: :blueprintid) end
    end

    test "rejects empty string key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique key must contain only lowercase letters and numbers/,
                   fn -> Unique.new!(key: "") end
    end
  end

  describe "new!/1 scope validation" do
    test "rejects invalid scope atom" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique scope must be one of/,
                   fn -> Unique.new!(key: "ok", scope: :invalid) end
    end

    test "rejects string scope" do
      # Arrange / Act / Assert
      assert_raise ArgumentError,
                   ~r/unique scope must be one of/,
                   fn -> Unique.new!(key: "ok", scope: "workflow") end
    end
  end

  describe "new!/1 missing key" do
    test "raises when key is not provided" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        Unique.new!(scope: :workflow)
      end
    end
  end
end
```

## Done when

- [ ] All 12 tests pass
- [ ] No compilation warnings
- [ ] `mix test test/hephaestus/core/workflow/unique_test.exs` green
