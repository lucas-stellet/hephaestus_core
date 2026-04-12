# Task 004: Refactor `Instance.new` to require explicit ID

**Wave**: 1 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-008, task-009

## Objective

Remove auto-generated UUID from `Instance.new` and require an explicit ID string. This is a breaking change — all existing constructors (`new/1`, `new/2`, `new/3`) are replaced with `new/4` that takes an ID parameter.

## Files

**Modify:** `lib/hephaestus/core/instance.ex` — replace constructors
**Modify:** `test/hephaestus/core/instance_test.exs` — update tests to pass explicit ID
**Modify:** `test/hephaestus/core/instance_v2_test.exs` — update tests to pass explicit ID

**Read:** `lib/hephaestus/core/instance.ex` — understand current constructors

## Requirements

### Remove
- `new/1` (workflow only)
- `new/2` (workflow + context, workflow + version)
- `new/3` (workflow + version + context)
- `generate_uuid/0` private function
- `band/2`, `bor/2`, `encode/2` private helpers (only used by UUID generation)

### Add
- `new/4` — `new(workflow, version, context, id)` where `id` is a binary string

```elixir
@spec new(module(), pos_integer(), map(), String.t()) :: t()
def new(workflow, version, context, id)
    when is_atom(workflow) and is_integer(version) and version > 0 and is_map(context) and is_binary(id) do
  %__MODULE__{
    id: id,
    workflow: workflow,
    workflow_version: version,
    context: Context.new(context)
  }
end
```

### Update tests

Every test that calls `Instance.new` must be updated to pass an explicit ID string. Use simple IDs like `"test::instance1"`, `"test::instance2"` etc. for test fixtures.

Search for all usages of `Instance.new` in the test files and update them.

## TDD Test Sequence

**Test file:** `test/hephaestus/core/instance_test.exs` (replace existing tests)

```elixir
defmodule Hephaestus.Core.InstanceTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Core.{Context, Instance}

  describe "new/4" do
    test "creates instance with explicit ID" do
      # Arrange
      workflow = MyTestWorkflow
      id = "orderid::abc123"

      # Act
      instance = Instance.new(workflow, 1, %{order_id: 123}, id)

      # Assert
      assert %Instance{
               id: "orderid::abc123",
               workflow: MyTestWorkflow,
               workflow_version: 1,
               status: :pending
             } = instance

      assert %Context{initial: %{order_id: 123}} = instance.context
    end

    test "preserves the exact ID provided" do
      # Arrange
      id = "blueprintid::550e8400-e29b-41d4-a716-446655440000"

      # Act
      instance = Instance.new(MyTestWorkflow, 1, %{}, id)

      # Assert
      assert instance.id == "blueprintid::550e8400-e29b-41d4-a716-446655440000"
    end

    test "initializes with empty active and completed steps" do
      # Arrange / Act
      instance = Instance.new(MyTestWorkflow, 1, %{}, "test::init")

      # Assert
      assert MapSet.size(instance.active_steps) == 0
      assert MapSet.size(instance.completed_steps) == 0
      assert instance.execution_history == []
    end

    test "sets workflow version" do
      # Arrange / Act
      instance = Instance.new(MyTestWorkflow, 3, %{}, "test::v3")

      # Assert
      assert instance.workflow_version == 3
    end

    test "initializes telemetry fields with defaults" do
      # Arrange / Act
      instance = Instance.new(MyTestWorkflow, 1, %{}, "test::telem")

      # Assert
      assert instance.telemetry_metadata == %{}
      assert instance.telemetry_start_time == nil
    end
  end

  describe "new/4 guards" do
    test "rejects non-binary ID" do
      # Arrange / Act / Assert
      assert_raise FunctionClauseError, fn ->
        Instance.new(MyTestWorkflow, 1, %{}, 123)
      end
    end

    test "rejects non-atom workflow" do
      # Arrange / Act / Assert
      assert_raise FunctionClauseError, fn ->
        Instance.new("NotAModule", 1, %{}, "test::guard")
      end
    end

    test "rejects zero version" do
      # Arrange / Act / Assert
      assert_raise FunctionClauseError, fn ->
        Instance.new(MyTestWorkflow, 0, %{}, "test::guard")
      end
    end
  end
end
```

## Done when

- [ ] All 8 tests pass
- [ ] `Instance.new/1`, `new/2`, `new/3` no longer exist (removed)
- [ ] `generate_uuid/0` and UUID helpers removed
- [ ] `test/hephaestus/core/instance_v2_test.exs` updated and passing
- [ ] `mix test test/hephaestus/core/instance_test.exs` green
