# Task 006: Add `Uniqueness.check/5` (scope-based uniqueness check)

**Wave**: 1 | **Effort**: M
**Depends on**: task-002, task-005
**Blocks**: task-010

## Objective

Add the `check/5` function to `Hephaestus.Uniqueness` that verifies uniqueness by querying Storage based on the configured scope. This function was intentionally left out of task-002.

## Files

**Modify:** `lib/hephaestus/uniqueness.ex` — add `check/5` with pattern matching on scope
**Modify:** `test/hephaestus/uniqueness_test.exs` — add tests for each scope

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

## Done when

- [ ] `check(%Unique{scope: :none}, ...)` returns `:ok` always
- [ ] `check(%Unique{scope: :workflow}, ...)` queries by id + workflow + active statuses
- [ ] `check(%Unique{scope: :version}, ...)` queries by id + workflow + version + active statuses
- [ ] `check(%Unique{scope: :global}, ...)` queries by id + active statuses only
- [ ] Returns `:ok` when no active instances found
- [ ] Returns `{:error, :already_running}` when active instances exist
- [ ] All tests pass
