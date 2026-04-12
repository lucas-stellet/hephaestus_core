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

## TDD Test Sequence

**Test file:** `test/hephaestus/runtime/runner/local_test.exs` (update existing)

```elixir
# Add/update in existing local runner test

describe "start_instance/3 with custom ID" do
  test "creates instance with the provided ID" do
    # Arrange
    opts = runner_opts() ++ [id: "testlinear::runner1", workflow_version: 1]

    # Act
    {:ok, id} = Runner.Local.start_instance(
      Hephaestus.Test.LinearWorkflow, %{}, opts
    )

    # Assert
    assert id == "testlinear::runner1"
  end

  test "stores instance with the provided ID in storage" do
    # Arrange
    opts = runner_opts() ++ [id: "testlinear::runner2", workflow_version: 1]

    # Act
    {:ok, id} = Runner.Local.start_instance(
      Hephaestus.Test.LinearWorkflow, %{}, opts
    )

    # Assert
    {storage_mod, storage_name} = opts[:storage]
    {:ok, instance} = storage_mod.get(storage_name, id)
    assert instance.id == "testlinear::runner2"
  end

  test "raises when :id is not provided" do
    # Arrange
    opts = runner_opts() ++ [workflow_version: 1]

    # Act / Assert
    assert_raise KeyError, ~r/key :id not found/, fn ->
      Runner.Local.start_instance(Hephaestus.Test.LinearWorkflow, %{}, opts)
    end
  end
end

describe "resume/2 with custom ID" do
  test "resumes instance by custom ID" do
    # Arrange
    opts = runner_opts() ++ [id: "testevent::resume1", workflow_version: 1]
    {:ok, id} = Runner.Local.start_instance(
      Hephaestus.Test.EventWorkflow, %{}, opts
    )
    Process.sleep(50)  # let it advance to waiting

    # Act
    result = Runner.Local.resume(id, :payment_confirmed)

    # Assert
    assert result == :ok
  end
end
```

## Done when

- [ ] All 4 tests pass
- [ ] Existing runner tests updated with `id:` and passing
- [ ] `mix test test/hephaestus/runtime/runner/local_test.exs` green
- [ ] `mix test test/hephaestus/runtime/runner/local_v2_test.exs` green
