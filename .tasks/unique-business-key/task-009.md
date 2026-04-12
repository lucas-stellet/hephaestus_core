# Task 009: Update `Runner.Local` to accept custom ID

**Wave**: 2 | **Effort**: M
**Depends on**: task-004, task-008
**Blocks**: task-011

## Objective

Update the local runner to use the explicit ID from opts instead of the auto-generated UUID from `Instance.new`. The runner receives `id:` in opts and passes it to `Instance.new/4`.

## Files

**Modify:** `lib/hephaestus/runtime/runner/local.ex` — update `start_instance`
**Modify:** `test/hephaestus/runtime/runner/local_test.exs` — update tests
**Modify:** `test/hephaestus/runtime/runner/local_v2_test.exs` — update tests

**Read:** `lib/hephaestus/core/instance.ex` — understand new `Instance.new/4` (from task-004)

## Requirements

### Update `start_instance/3`

In `Runner.Local.start_instance/3` (line 78), change the instance creation from:

```elixir
# Before
instance = %{Instance.new(workflow, version, context) | telemetry_metadata: telemetry_metadata}
```

To:

```elixir
# After
id = Keyword.fetch!(opts, :id)
instance = %{Instance.new(workflow, version, context, id) | telemetry_metadata: telemetry_metadata}
```

The rest of the function stays the same — `instance.id` is already used for registry lookup and storage.

### Update tests

All tests in `local_test.exs` and `local_v2_test.exs` that call `start_instance` via the runner or via `Hephaestus.Test.Hephaestus.start_instance` need to pass `id:` in opts.

Search for patterns like:
- `start_instance(workflow, context, ...)`
- `Hephaestus.Test.Hephaestus.start_instance(...)`

Add `id: "test::instanceN"` (use unique IDs per test to avoid conflicts in async tests).

## Done when

- [ ] `Runner.Local.start_instance(MyWorkflow, ctx, id: "test::abc", ...)` creates instance with that ID
- [ ] The instance ID in storage matches the provided ID
- [ ] `resume/2` works with the custom ID
- [ ] All local runner tests pass
- [ ] All local runner v2 tests pass
