# Task E02: Update Ecto runner to accept custom ID

**Wave**: E0 (after core complete) | **Effort**: M
**Depends on**: core complete (task-011)
**Blocks**: task-O01
**Repo**: hephaestus_ecto

## Objective

Update the Ecto runner's `start_instance/3` to accept the `:id` option and pass it to `Instance.new/4` instead of relying on auto-generated UUID.

## Requirements

In the Ecto runner's `start_instance/3`:

```elixir
def start_instance(workflow, context, opts) do
  id = Keyword.fetch!(opts, :id)  # required now
  version = Keyword.get(opts, :workflow_version, 1)

  instance = Instance.new(workflow, version, context, id)
  # ... rest of implementation
end
```

### Test updates

Update all test workflows to include `unique:` and all `start_instance` calls to pass `id:`.

### Version bump

Bump package version to `0.2.0`. Update CHANGELOG.md.

## Done when

- [ ] `start_instance` accepts and uses custom ID
- [ ] Instance is stored with the provided ID
- [ ] All tests pass
- [ ] CHANGELOG.md updated
