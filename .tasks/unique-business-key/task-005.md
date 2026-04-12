# Task 005: Extend `Storage.ETS` with new query filters

**Wave**: 1 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-006

## Objective

Add support for `:id`, `:workflow_version`, and `:status_in` filters to the ETS storage adapter's `query/1` implementation. The `Storage` behaviour's `query/1` callback already exists — this extends the filter handling in the ETS implementation.

## Files

**Modify:** `test/hephaestus/runtime/storage/ets_test.exs` — add tests for new filters first
**Modify:** `lib/hephaestus/runtime/storage/ets.ex` — extend `matches_filters?/2`

**Read:** `lib/hephaestus/runtime/storage.ex` — understand the behaviour contract

## TDD Execution Order

### Phase 1: RED — Add new test describe blocks first

Add test blocks for `:id`, `:status_in`, `:workflow_version`, and combined filters to the existing ETS test file. Use `%Instance{}` struct literals for fixtures (avoids dependency on Instance.new changes from task-004 running in parallel). Tests will fail because ETS doesn't support these filters yet.

### Phase 2: GREEN — Extend matches_filters?/2

Add new filter clauses to `matches_filters?/2` in `storage/ets.ex`:

```elixir
{:status_in, statuses} -> instance.status in statuses
{:workflow_version, v} -> instance.workflow_version == v
{:id, id} -> instance.id == id
```

### Phase 3: REFACTOR — Clean up if needed
3. Filter by `:workflow_version` — exact version match
4. Combined filters: `:id` + `:workflow` + `:status_in`
5. Empty filters still return all instances

## TDD Test Sequence

**Test file:** `test/hephaestus/runtime/storage/ets_test.exs` (add new describe blocks)

Add these tests to the existing ETS test file. Use `%Instance{}` struct literals to create fixtures (avoids dependency on `Instance.new` changes from task-004 which runs in parallel).

```elixir
# Add to existing ETSTest module

describe "query/1 with :id filter" do
  test "returns instance matching exact ID", %{storage: storage} do
    # Arrange
    instance_a = %Instance{id: "test::abc", workflow: TestWorkflow, workflow_version: 1, status: :pending, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    instance_b = %Instance{id: "test::def", workflow: TestWorkflow, workflow_version: 1, status: :pending, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    :ok = ETSStorage.put(storage, instance_a)
    :ok = ETSStorage.put(storage, instance_b)

    # Act
    results = ETSStorage.query(storage, id: "test::abc")

    # Assert
    assert length(results) == 1
    assert hd(results).id == "test::abc"
  end
end

describe "query/1 with :status_in filter" do
  test "returns instances matching any of the given statuses", %{storage: storage} do
    # Arrange
    pending = %Instance{id: "test::s1", workflow: TestWorkflow, workflow_version: 1, status: :pending, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    running = %Instance{id: "test::s2", workflow: TestWorkflow, workflow_version: 1, status: :running, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    completed = %Instance{id: "test::s3", workflow: TestWorkflow, workflow_version: 1, status: :completed, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    :ok = ETSStorage.put(storage, pending)
    :ok = ETSStorage.put(storage, running)
    :ok = ETSStorage.put(storage, completed)

    # Act
    results = ETSStorage.query(storage, status_in: [:pending, :running])

    # Assert
    assert length(results) == 2
    assert Enum.all?(results, & &1.status in [:pending, :running])
  end
end

describe "query/1 with :workflow_version filter" do
  test "returns instances matching the given version", %{storage: storage} do
    # Arrange
    v1 = %Instance{id: "test::v1", workflow: TestWorkflow, workflow_version: 1, status: :pending, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    v2 = %Instance{id: "test::v2", workflow: TestWorkflow, workflow_version: 2, status: :pending, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    :ok = ETSStorage.put(storage, v1)
    :ok = ETSStorage.put(storage, v2)

    # Act
    results = ETSStorage.query(storage, workflow_version: 2)

    # Assert
    assert length(results) == 1
    assert hd(results).workflow_version == 2
  end
end

describe "query/1 with combined filters" do
  test "applies all filters with AND semantics", %{storage: storage} do
    # Arrange
    target = %Instance{id: "test::target", workflow: WorkflowA, workflow_version: 2, status: :waiting, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    decoy1 = %Instance{id: "test::target", workflow: WorkflowB, workflow_version: 2, status: :waiting, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    decoy2 = %Instance{id: "test::other", workflow: WorkflowA, workflow_version: 2, status: :completed, context: %Hephaestus.Core.Context{initial: %{}, steps: %{}}, step_configs: %{}, active_steps: MapSet.new(), completed_steps: MapSet.new(), runtime_metadata: %{}, execution_history: [], telemetry_metadata: %{}, telemetry_start_time: nil}
    :ok = ETSStorage.put(storage, target)
    :ok = ETSStorage.put(storage, decoy1)
    :ok = ETSStorage.put(storage, decoy2)

    # Act
    results = ETSStorage.query(storage, id: "test::target", workflow: WorkflowA, status_in: [:waiting])

    # Assert
    assert length(results) == 1
    assert hd(results).id == "test::target"
    assert hd(results).workflow == WorkflowA
  end
end
```

## Done when

- [ ] All 4 new test groups pass
- [ ] Existing ETS tests still pass (no regressions)
- [ ] `mix test test/hephaestus/runtime/storage/ets_test.exs` green
