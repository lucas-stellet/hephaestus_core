# Task 002: Create `Hephaestus.Uniqueness` module (ID build, validate, extract)

**Wave**: 0 | **Effort**: M
**Depends on**: none
**Blocks**: task-006, task-010

## Objective

Create the `Hephaestus.Uniqueness` module that handles composite ID construction, value validation, and value extraction. This task does NOT include `check/5` (that's task-006).

## Files

**Create:** `test/hephaestus/uniqueness_test.exs` — tests for build/validate/extract
**Create:** `lib/hephaestus/uniqueness.ex` — the Uniqueness module

## TDD Execution Order

### Phase 1: RED — Write all tests first

Create the test file. Create a minimal module stub so tests compile but fail.

### Phase 2: GREEN — Implement to make tests pass

- `build_id/2` — takes `%Unique{}` + value string, returns `"key::value"`. Calls `validate_value!` first.
- `build_id_with_suffix/2` — same but appends random 8-char hex suffix via `:crypto.strong_rand_bytes(4)`.
- `validate_value!/1` — value must be `[a-z0-9]+` or UUID (`[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`). `-` ONLY inside valid UUIDs. Raises `ArgumentError`.
- `extract_value/1` — splits on `::`, returns second segment. Handles 2-part (`key::value`) and 3-part (`key::value::suffix`) IDs.

### Phase 3: REFACTOR — Clean up if needed

## Tests

**Test file:** `test/hephaestus/uniqueness_test.exs`

```elixir
defmodule Hephaestus.UniquenessTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Uniqueness
  alias Hephaestus.Workflow.Unique

  describe "build_id/2" do
    test "constructs composite ID with key and value" do
      # Arrange
      unique = %Unique{key: "blueprintid", scope: :workflow}

      # Act
      id = Uniqueness.build_id(unique, "abc123")

      # Assert
      assert id == "blueprintid::abc123"
    end

    test "constructs composite ID with UUID value" do
      # Arrange
      unique = %Unique{key: "blueprintid", scope: :workflow}
      uuid = "550e8400-e29b-41d4-a716-446655440000"

      # Act
      id = Uniqueness.build_id(unique, uuid)

      # Assert
      assert id == "blueprintid::550e8400-e29b-41d4-a716-446655440000"
    end

    test "raises on invalid value" do
      # Arrange
      unique = %Unique{key: "bp", scope: :workflow}

      # Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.build_id(unique, "ABC-invalid")
      end
    end
  end

  describe "build_id_with_suffix/2" do
    test "constructs composite ID with random suffix" do
      # Arrange
      unique = %Unique{key: "userid", scope: :none}

      # Act
      id = Uniqueness.build_id_with_suffix(unique, "abc123")

      # Assert
      assert String.starts_with?(id, "userid::abc123::")
      [_key, _value, suffix] = String.split(id, "::")
      assert byte_size(suffix) == 8
      assert Regex.match?(~r/^[a-f0-9]{8}$/, suffix)
    end

    test "generates unique suffixes on each call" do
      # Arrange
      unique = %Unique{key: "userid", scope: :none}

      # Act
      id1 = Uniqueness.build_id_with_suffix(unique, "abc123")
      id2 = Uniqueness.build_id_with_suffix(unique, "abc123")

      # Assert
      refute id1 == id2
    end
  end

  describe "validate_value!/1" do
    test "accepts lowercase alphanumeric" do
      # Arrange / Act / Assert
      assert Uniqueness.validate_value!("abc123") == :ok
    end

    test "accepts valid UUID with hyphens" do
      # Arrange / Act / Assert
      assert Uniqueness.validate_value!("550e8400-e29b-41d4-a716-446655440000") == :ok
    end

    test "rejects uppercase letters" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value: "ABC"/, fn ->
        Uniqueness.validate_value!("ABC")
      end
    end

    test "rejects hyphens outside UUID format" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value: "abc-123"/, fn ->
        Uniqueness.validate_value!("abc-123")
      end
    end

    test "rejects underscores" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc_123")
      end
    end

    test "rejects double colon separator" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc::123")
      end
    end

    test "rejects spaces" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("abc 123")
      end
    end

    test "rejects empty string" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        Uniqueness.validate_value!("")
      end
    end
  end

  describe "extract_value/1" do
    test "extracts value from simple composite ID" do
      # Arrange
      id = "blueprintid::abc123"

      # Act
      value = Uniqueness.extract_value(id)

      # Assert
      assert value == "abc123"
    end

    test "extracts value from suffixed composite ID" do
      # Arrange
      id = "userid::abc123::a1b2c3d4"

      # Act
      value = Uniqueness.extract_value(id)

      # Assert
      assert value == "abc123"
    end

    test "extracts UUID value from composite ID" do
      # Arrange
      id = "blueprintid::550e8400-e29b-41d4-a716-446655440000"

      # Act
      value = Uniqueness.extract_value(id)

      # Assert
      assert value == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "raises on malformed ID without separator" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid unique id format/, fn ->
        Uniqueness.extract_value("noseparator")
      end
    end
  end
end
```

## Done when

- [ ] All 16 tests pass
- [ ] No compilation warnings
- [ ] `mix test test/hephaestus/uniqueness_test.exs` green
