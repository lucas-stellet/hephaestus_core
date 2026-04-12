# Task E01: Extend Ecto storage query with new filters

**Wave**: E0 (after core complete) | **Effort**: M
**Depends on**: core complete (task-011)
**Blocks**: task-O01
**Repo**: hephaestus_ecto

## Objective

Update the Ecto storage adapter to support the new query filters (`:id`, `:workflow_version`, `:status_in`) that the Uniqueness module uses for scope-based checks.

## Requirements

The Ecto storage `query/1` implementation needs to build Ecto queries with the new filters:

```elixir
# :id filter
where(query, [w], w.id == ^id)

# :workflow_version filter
where(query, [w], w.workflow_version == ^version)

# :status_in filter
where(query, [w], w.status in ^statuses)
```

No schema change needed — the `workflow_instances` table already has `id`, `workflow`, `workflow_version`, and `status` columns.

### Tests

1. Query by `:id` — exact match returns correct instance
2. Query by `:status_in` — returns instances with matching statuses
3. Query by `:workflow_version` — filters by version
4. Combined filters with AND semantics
5. Existing `:status` and `:workflow` filters still work

### Version bump

Update `mix.exs` dependency: `{:hephaestus_core, "~> 0.2.0"}`. Bump package version to `0.2.0`.

## Done when

- [ ] New filters work in Ecto storage query
- [ ] All existing tests still pass
- [ ] New filter tests pass
- [ ] Dependency on core ~> 0.2.0
