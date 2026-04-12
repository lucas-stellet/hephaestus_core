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

## Done when

- [ ] `Instance.new(MyWorkflow, 1, %{}, "test::abc123")` creates instance with that ID
- [ ] `Instance.new/1`, `new/2`, `new/3` no longer exist
- [ ] `generate_uuid/0` and related helpers removed
- [ ] All instance tests pass with explicit IDs
- [ ] No compilation warnings
