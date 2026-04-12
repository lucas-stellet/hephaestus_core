# Task 006: Add `Uniqueness.check/5` (scope-based uniqueness check)

**Wave**: 1 | **Effort**: M
**Depends on**: task-002, task-005
**Blocks**: task-010

## Objective

Add the `check/5` function to `Hephaestus.Uniqueness` that verifies uniqueness by querying Storage based on the configured scope. This function was intentionally left out of task-002.

## Files

**Modify:** `test/hephaestus/uniqueness_test.exs` — add check/5 tests for each scope first
**Modify:** `lib/hephaestus/uniqueness.ex` — add `check/5` with pattern matching on scope

## TDD Execution Order

### Phase 1: RED — Add check/5 tests to existing test file

Add new describe blocks to the uniqueness test file from task-002. Tests fail because `check/5` doesn't exist yet.

### Phase 2: GREEN — Implement check/5

### Phase 3: REFACTOR — Clean up if needed

## Requirements

### Signature

```elixir
@spec check(Unique.t(), String.t(), module(), pos_integer(), (keyword() -> [Instance.t()])) ::
  :ok | {:error, :already_running}
def check(unique, id, workflow, version, query_fn)
```

The `query_fn` is a closure that calls `Storage.query/1` — this keeps the Uniqueness module decoupled from specific storage implementations.

### Implementation by scope

```elixir
@active_statuses [:pending, :running, :waiting]

# scope: :none — no check, always ok
def check(%Unique{scope: :none}, _id, _workflow, _version, _query_fn), do: :ok

# scope: :workflow — unique per {id, workflow_module}
def check(%Unique{scope: :workflow}, id, workflow, _version, query_fn) do
  case query_fn.(id: id, workflow: workflow, status_in: @active_statuses) do
    [] -> :ok
    [_ | _] -> {:error, :already_running}
  end
end

# scope: :version — unique per {id, workflow_module, version}
def check(%Unique{scope: :version}, id, workflow, version, query_fn) do
  case query_fn.(id: id, workflow: workflow, workflow_version: version, status_in: @active_statuses) do
    [] -> :ok
    [_ | _] -> {:error, :already_running}
  end
end

# scope: :global — unique per {id}
def check(%Unique{scope: :global}, id, _workflow, _version, query_fn) do
  case query_fn.(id: id, status_in: @active_statuses) do
    [] -> :ok
    [_ | _] -> {:error, :already_running}
  end
end
```

### Tests

Use a mock `query_fn` (simple function that returns a list) to test:

1. `scope: :none` always returns `:ok` regardless of what query_fn would return
2. `scope: :workflow` — returns `:ok` when query_fn returns `[]`, `{:error, :already_running}` when non-empty
3. `scope: :version` — same pattern, verify version is included in filters
4. `scope: :global` — same pattern, verify only id + status_in are passed
5. Verify the correct filter keywords are passed to query_fn for each scope (capture the args)

## TDD Test Sequence

**Test file:** `test/hephaestus/uniqueness_test.exs` (add to existing file from task-002)

```elixir
# Add to existing UniquenessTest module

describe "check/5 with scope :none" do
  test "always returns :ok regardless of existing instances" do
    # Arrange
    unique = %Unique{key: "userid", scope: :none}
    query_fn = fn _filters -> [%{id: "userid::abc123"}] end

    # Act
    result = Uniqueness.check(unique, "userid::abc123", SomeWorkflow, 1, query_fn)

    # Assert
    assert result == :ok
  end
end

describe "check/5 with scope :workflow" do
  test "returns :ok when no active instances exist" do
    # Arrange
    unique = %Unique{key: "bp", scope: :workflow}
    query_fn = fn _filters -> [] end

    # Act
    result = Uniqueness.check(unique, "bp::abc123", MyWorkflow, 1, query_fn)

    # Assert
    assert result == :ok
  end

  test "returns {:error, :already_running} when active instance exists" do
    # Arrange
    unique = %Unique{key: "bp", scope: :workflow}
    query_fn = fn _filters -> [%{id: "bp::abc123"}] end

    # Act
    result = Uniqueness.check(unique, "bp::abc123", MyWorkflow, 1, query_fn)

    # Assert
    assert result == {:error, :already_running}
  end

  test "passes correct filters: id, workflow, status_in" do
    # Arrange
    unique = %Unique{key: "bp", scope: :workflow}
    test_pid = self()

    query_fn = fn filters ->
      send(test_pid, {:filters, filters})
      []
    end

    # Act
    Uniqueness.check(unique, "bp::abc123", MyWorkflow, 2, query_fn)

    # Assert
    assert_received {:filters, filters}
    assert Keyword.get(filters, :id) == "bp::abc123"
    assert Keyword.get(filters, :workflow) == MyWorkflow
    assert Keyword.get(filters, :status_in) == [:pending, :running, :waiting]
    refute Keyword.has_key?(filters, :workflow_version)
  end
end

describe "check/5 with scope :version" do
  test "returns :ok when no active instances for that version" do
    # Arrange
    unique = %Unique{key: "bp", scope: :version}
    query_fn = fn _filters -> [] end

    # Act
    result = Uniqueness.check(unique, "bp::abc123", MyWorkflow, 2, query_fn)

    # Assert
    assert result == :ok
  end

  test "passes workflow_version in filters" do
    # Arrange
    unique = %Unique{key: "bp", scope: :version}
    test_pid = self()

    query_fn = fn filters ->
      send(test_pid, {:filters, filters})
      []
    end

    # Act
    Uniqueness.check(unique, "bp::abc123", MyWorkflow, 2, query_fn)

    # Assert
    assert_received {:filters, filters}
    assert Keyword.get(filters, :id) == "bp::abc123"
    assert Keyword.get(filters, :workflow) == MyWorkflow
    assert Keyword.get(filters, :workflow_version) == 2
    assert Keyword.get(filters, :status_in) == [:pending, :running, :waiting]
  end
end

describe "check/5 with scope :global" do
  test "returns :ok when no active instances globally" do
    # Arrange
    unique = %Unique{key: "companyid", scope: :global}
    query_fn = fn _filters -> [] end

    # Act
    result = Uniqueness.check(unique, "companyid::abc123", AnyWorkflow, 1, query_fn)

    # Assert
    assert result == :ok
  end

  test "only passes id and status_in in filters (no workflow)" do
    # Arrange
    unique = %Unique{key: "companyid", scope: :global}
    test_pid = self()

    query_fn = fn filters ->
      send(test_pid, {:filters, filters})
      []
    end

    # Act
    Uniqueness.check(unique, "companyid::abc123", SomeWorkflow, 1, query_fn)

    # Assert
    assert_received {:filters, filters}
    assert Keyword.get(filters, :id) == "companyid::abc123"
    assert Keyword.get(filters, :status_in) == [:pending, :running, :waiting]
    refute Keyword.has_key?(filters, :workflow)
    refute Keyword.has_key?(filters, :workflow_version)
  end
end
```

## Done when

- [ ] All 8 new tests pass (adding to existing uniqueness tests from task-002)
- [ ] `mix test test/hephaestus/uniqueness_test.exs` green (all 24 tests)
