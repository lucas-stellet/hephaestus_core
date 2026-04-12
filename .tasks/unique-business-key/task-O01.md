# Task O01: Update Oban runner to accept custom ID + advisory lock

**Wave**: O0 (after ecto complete) | **Effort**: L
**Depends on**: ecto complete (task-E01, task-E02)
**Repo**: hephaestus_oban

## Objective

Update the Oban runner to accept the `:id` option and pass it to `Instance.new/4`. Add advisory lock around the uniqueness check + insert sequence to prevent race conditions in multi-node environments.

## Requirements

### Runner update

In the Oban runner's `start_instance/3`, fetch the ID from opts:

```elixir
id = Keyword.fetch!(opts, :id)
instance = Instance.new(workflow, version, context, id)
```

The worker args already carry `instance_id` as string — no change needed there since the ID format changed from UUID to composite but is still a string.

### Advisory lock for uniqueness

The check-and-create sequence is not atomic. In multi-node Oban environments:

1. Node A checks: no instance with ID "blueprintid::abc123" → OK
2. Node B checks: no instance with ID "blueprintid::abc123" → OK
3. Both create → duplicate

Wrap the sequence in a transaction with advisory lock:

```sql
SELECT pg_advisory_xact_lock(hashtext('blueprintid::abc123'));
```

In Elixir:

```elixir
Repo.transaction(fn ->
  lock_key = :erlang.phash2(id)
  Ecto.Adapters.SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1)", [lock_key])

  # Now check + insert is atomic within this transaction
  case storage.query(filters) do
    [] -> insert_instance(instance)
    [_ | _] -> Repo.rollback(:already_running)
  end
end)
```

This is the runner's responsibility, not the Uniqueness module's.

### Test updates

Update test workflows and `start_instance` calls. Test the advisory lock behavior if possible (may need integration test with real DB).

### Version bump

Update `mix.exs` dependencies: `{:hephaestus_core, "~> 0.2.0"}`, `{:hephaestus_ecto, "~> 0.2.0"}`. Bump package version to `0.4.0`. Update CHANGELOG.md.

## Done when

- [ ] Oban runner accepts and uses custom ID
- [ ] Advisory lock prevents duplicate creation in concurrent scenarios
- [ ] All existing tests pass with updated IDs
- [ ] CHANGELOG.md updated
