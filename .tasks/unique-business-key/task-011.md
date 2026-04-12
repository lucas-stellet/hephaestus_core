# Task 011: Update all test support files and run full integration tests

**Wave**: 4 | **Effort**: L
**Depends on**: task-009, task-010
**Blocks**: task-E01, task-E02

## Objective

Update all existing test support files (workflow definitions, step definitions, test hephaestus module) to work with the new mandatory `unique:` option and explicit IDs. Run the full test suite and fix any remaining failures. Update CHANGELOG.md.

## Files

**Modify:** `test/support/test_workflows.ex` — add `unique:` to all workflow definitions
**Modify:** `test/support/test_workflows_v2.ex` — add `unique:` to all workflow definitions
**Modify:** `test/support/test_versioned_workflows.ex` — add `unique:` to versioned workflows
**Modify:** `test/support/test_hephaestus.ex` — verify works with Tracker
**Modify:** `test/support/tuple_config_hephaestus.ex` — verify works
**Modify:** `test/hephaestus/versioned_workflow_integration_test.exs` — update integration tests
**Modify:** `test/hephaestus/telemetry_test.exs` — update to pass explicit IDs
**Modify:** `test/hephaestus/telemetry/log_handler_test.exs` — update
**Modify:** `test/hephaestus/telemetry/metrics_test.exs` — update
**Modify:** `test/hephaestus/core/engine_v2_test.exs` — update
**Modify:** `test/hephaestus/core/workflow_v2_test.exs` — update
**Modify:** `test/hephaestus/core/workflow_versioning_test.exs` — update
**Modify:** `test/hephaestus/core/workflow_tags_test.exs` — update
**Modify:** `test/hephaestus/steps/builtin_steps_v2_test.exs` — update
**Modify:** `test/hephaestus/runtime/runner/local_telemetry_test.exs` — update
**Modify:** `CHANGELOG.md` — add [Unreleased] entries

## Requirements

### Test workflow updates

Every `use Hephaestus.Workflow` needs `unique:` added. Use the workflow name as the key:

```elixir
# Before
defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow
  ...
end

# After
defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow,
    unique: [key: "testlinear"]
  ...
end
```

For versioned workflows:
```elixir
defmodule Hephaestus.Test.VersionedWorkflow do
  use Hephaestus.Workflow,
    versions: %{1 => V1, 2 => V2},
    current: 2,
    unique: [key: "testversioned"]
end
```

### Test call updates

Every `start_instance` call needs `id:`:

```elixir
# Before
{:ok, id} = Hephaestus.Test.Hephaestus.start_instance(LinearWorkflow, %{})

# After
{:ok, id} = Hephaestus.Test.Hephaestus.start_instance(LinearWorkflow, %{}, id: "testlinear::test1")
```

Use unique IDs per test to avoid conflicts. Pattern: `"key::testname"`.

### CHANGELOG.md

Add under `[Unreleased]`:

```markdown
### Added
- Mandatory business key (`unique:` option) for all workflows
- `Hephaestus.Workflow.Unique` struct for uniqueness configuration
- `Hephaestus.Uniqueness` module for composite ID construction and validation
- `Hephaestus.Instances` auto-discovery registry for Hephaestus modules
- Workflow facade functions: `start/2`, `resume/2`, `get/1`, `list/1`, `cancel/1`
- Uniqueness scopes: `:workflow`, `:version`, `:global`, `:none`
- New Storage query filters: `:id`, `:workflow_version`, `:status_in`

### Changed
- `Instance.new` now requires explicit ID parameter (no more auto-generated UUID)
- `start_instance` requires `:id` option
- Composite ID format: `"key::value"` with `::` separator

### Removed
- Auto-generated UUID for instance IDs
```

### Final validation

Run `mix test` and ensure ALL tests pass. Fix any remaining compilation errors or test failures.

## Done when

- [ ] All test workflow modules have `unique:` configured
- [ ] All `start_instance` calls pass explicit `id:`
- [ ] `mix test` passes with zero failures
- [ ] No compilation warnings
- [ ] CHANGELOG.md updated
