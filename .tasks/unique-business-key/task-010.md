# Task 010: Generate facade functions in Workflow macro

**Wave**: 3 | **Effort**: L
**Depends on**: task-006, task-007, task-008
**Blocks**: task-011

## Objective

The most complex task. Extend the Workflow macro to generate facade functions (`start/2`, `resume/2`, `get/1`, `list/1`, `cancel/1`) in umbrella and standalone workflow modules. These functions construct the composite ID via `Hephaestus.Uniqueness` and delegate to the Hephaestus module discovered via `Hephaestus.Instances`.

## Files

**Modify:** `lib/hephaestus/core/workflow.ex` — add facade generation in both umbrella and standard compile paths
**Create:** `test/hephaestus/core/workflow_facade_test.exs` — comprehensive facade tests

**Read:** `lib/hephaestus/uniqueness.ex` — Uniqueness module
**Read:** `lib/hephaestus/instances.ex` — Instances registry
**Read:** `lib/hephaestus/core/workflow/unique.ex` — Unique struct

## Requirements

### Facade functions to generate

For scopes OTHER than `:none`, generate all 5 functions:

```elixir
def start(value, context) do
  hephaestus = resolve_hephaestus()
  unique = __unique__()
  id = Hephaestus.Uniqueness.build_id(unique, value)

  with :ok <- Hephaestus.Uniqueness.check(unique, id, __MODULE__, current_version(), &storage_query/1) do
    hephaestus.start_instance(__MODULE__, context, id: id)
  end
end

def resume(value, event) do
  hephaestus = resolve_hephaestus()
  id = Hephaestus.Uniqueness.build_id(__unique__(), value)
  hephaestus.resume(id, event)
end

def get(value) do
  {storage_mod, storage_name} = resolve_storage()
  id = Hephaestus.Uniqueness.build_id(__unique__(), value)
  storage_mod.get(storage_name, id)
end

def list(filters \\ []) do
  {storage_mod, storage_name} = resolve_storage()
  storage_mod.query(storage_name, [{:workflow, __MODULE__} | filters])
end

def cancel(value) do
  {storage_mod, storage_name} = resolve_storage()
  id = Hephaestus.Uniqueness.build_id(__unique__(), value)

  with {:ok, instance} <- storage_mod.get(storage_name, id) do
    if instance.status in [:pending, :running, :waiting] do
      storage_mod.put(storage_name, %{instance | status: :cancelled})
    else
      {:error, :not_cancellable}
    end
  end
end
```

For `scope: :none`, generate only `start/2` and `list/1`:
- `start/2` uses `build_id_with_suffix/2` and skips `check/5`
- `resume/2`, `get/1`, `cancel/1` are NOT generated

### Helper functions to generate

```elixir
defp resolve_hephaestus do
  # Use compile-time __hephaestus__() if set, otherwise runtime lookup
  case __hephaestus__() do
    nil -> Hephaestus.Instances.lookup!()
    module -> module
  end
end

defp resolve_storage do
  hephaestus = resolve_hephaestus()
  # Need to get storage config from the hephaestus module
  # This requires the hephaestus module to expose storage info
end

defp storage_query(filters) do
  {storage_mod, storage_name} = resolve_storage()
  storage_mod.query(storage_name, filters)
end
```

### Storage access challenge

The facade needs access to the storage adapter. The `use Hephaestus` macro generates `runner_opts/0` as a private function. The facade needs a way to get the storage tuple `{module, name}`.

**Solution:** Add a public `__storage__/0` function to the Hephaestus entry-point module (in task-008's scope, but if not done there, add it here). The facade calls `resolve_hephaestus().__storage__()`.

If `__storage__/0` doesn't exist yet on the Hephaestus module, add it to `lib/hephaestus.ex` in the generated quote block:

```elixir
def __storage__ do
  {@hephaestus_storage_module, Module.concat(__MODULE__, Storage)}
end
```

### Version resolution for umbrella vs standalone

For umbrella: `current_version()` is already generated.
For standalone: `__version__()` is already generated. Use it.

The `start/2` needs to pass the workflow module to `start_instance` so the entry-point macro resolves the version. This already works — the facade calls `hephaestus.start_instance(__MODULE__, context, id: id)`.

### Tests

Create test workflows WITH `unique:` configured, start them via facade, and verify:

1. `MyWorkflow.start("abc123", ctx)` creates instance with correct composite ID
2. `MyWorkflow.resume("abc123", :event)` resumes the correct instance
3. `MyWorkflow.get("abc123")` returns the instance
4. `MyWorkflow.list()` returns instances for that workflow
5. `MyWorkflow.cancel("abc123")` cancels active instance
6. `MyWorkflow.cancel("abc123")` returns `{:error, :not_cancellable}` for completed
7. `MyWorkflow.start("abc123", ctx)` with `:reject` scope returns `{:error, :already_running}` on duplicate
8. `scope: :none` — start works, resume/get/cancel not available

## Done when

- [ ] Facade functions are generated for workflows with `unique:`
- [ ] `start/2` builds ID, checks uniqueness, delegates to Hephaestus
- [ ] `resume/2` builds ID and delegates
- [ ] `get/1` builds ID and queries storage
- [ ] `list/1` queries storage with workflow filter
- [ ] `cancel/1` validates status and updates
- [ ] `scope: :none` only generates `start/2` and `list/1`
- [ ] `scope: :workflow` rejects duplicates correctly
- [ ] Hephaestus module is discovered via Instances registry
- [ ] All tests pass
