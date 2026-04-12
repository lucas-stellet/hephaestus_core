# Task O02: Update Oban storage query filters

**Wave**: O0 (after ecto complete) | **Effort**: M
**Depends on**: ecto complete (task-E01, task-E02)
**Repo**: hephaestus_oban

## Objective

Ensure the Oban storage adapter supports the new query filters. Since hephaestus_oban queries the `workflow_instances` table via hephaestus_ecto, this may be mostly inherited. Verify and add any Oban-specific filter handling.

## Requirements

### Verify inherited filters

The Oban storage adapter delegates to the Ecto storage for `workflow_instances` queries. Verify that the new filters (`:id`, `:workflow_version`, `:status_in`) from task-E01 work through the Oban storage layer.

### Oban-specific considerations

If the Oban storage has its own query implementation (not delegating to Ecto), add the same filters:

```elixir
{:id, id} -> where(query, [w], w.id == ^id)
{:workflow_version, v} -> where(query, [w], w.workflow_version == ^v)
{:status_in, statuses} -> where(query, [w], w.status in ^statuses)
```

### Tests

1. Verify filters work through the Oban storage layer
2. Test combined filters
3. Ensure existing query behavior unchanged

### Version bump

Bump to `0.4.0`. Update CHANGELOG.md.

## Done when

- [ ] New filters work through Oban storage
- [ ] All existing tests pass
- [ ] CHANGELOG.md updated
