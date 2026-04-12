# Task 005: Extend `Storage.ETS` with new query filters

**Wave**: 1 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-006

## Objective

Add support for `:id`, `:workflow_version`, and `:status_in` filters to the ETS storage adapter's `query/1` implementation. The `Storage` behaviour's `query/1` callback already exists — this extends the filter handling in the ETS implementation.

## Files

**Modify:** `lib/hephaestus/runtime/storage/ets.ex` — extend `matches_filters?/2`
**Modify:** `test/hephaestus/runtime/storage/ets_test.exs` — add tests for new filters

**Read:** `lib/hephaestus/runtime/storage.ex` — understand the behaviour contract

## Requirements

The current `matches_filters?/2` in `storage/ets.ex` (line 139-144) handles `:status` and `:workflow`. Add:

```elixir
defp matches_filters?(%Instance{} = instance, filters) do
  Enum.all?(filters, fn
    {:status, status} -> instance.status == status
    {:status_in, statuses} -> instance.status in statuses
    {:workflow, workflow} -> instance.workflow == workflow
    {:workflow_version, v} -> instance.workflow_version == v
    {:id, id} -> instance.id == id
    {_key, _value} -> true
  end)
end
```

### Test scenarios

Test with instances that have explicit IDs (use `"test::abc"` format since Instance.new now requires ID — but this task runs in parallel with task-004, so create instances directly with `%Instance{id: "...", ...}` struct syntax for test fixtures).

1. Filter by `:id` — exact match
2. Filter by `:status_in` — list of statuses
3. Filter by `:workflow_version` — exact version match
4. Combined filters: `:id` + `:workflow` + `:status_in`
5. Empty filters still return all instances

## Done when

- [ ] `query(id: "test::abc")` returns only the matching instance
- [ ] `query(status_in: [:running, :waiting])` returns instances with those statuses
- [ ] `query(workflow_version: 2)` filters by version
- [ ] Combined filters work with AND semantics
- [ ] Existing `:status` and `:workflow` filters still work
- [ ] All tests pass
