# Task 003: Create `Hephaestus.Instances` registry + Tracker

**Wave**: 0 | **Effort**: M
**Depends on**: none
**Blocks**: task-008, task-010

## Objective

Create the auto-discovery mechanism that allows workflow facades to find the Hephaestus module without explicit configuration. Uses Elixir's `Registry` (same pattern as Oban).

## Files

**Create:** `lib/hephaestus/instances.ex` — registry module with `register/1` and `lookup!/0`
**Create:** `lib/hephaestus/instances/tracker.ex` — GenServer that registers on init, auto-deregisters on death
**Create:** `test/hephaestus/instances_test.exs` — tests for register, lookup, multi-instance error

## Requirements

### `Hephaestus.Instances`

- `child_spec/1` — creates a `Registry` child spec with `keys: :unique` and name `Hephaestus.Instances.Registry`
- `register/1` — registers the given module name in the registry. Called by the Tracker.
- `lookup!/0` — returns the single registered Hephaestus module. Raises if none or multiple found.

```elixir
def lookup! do
  case Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
    [single] -> single
    [] -> raise "No Hephaestus instance running. Start one in your supervision tree."
    multiple -> raise "Multiple Hephaestus instances: #{inspect(multiple)}. " <>
                      "Pass hephaestus: MyApp.Hephaestus in your workflow's use options."
  end
end
```

### `Hephaestus.Instances.Tracker`

- A simple GenServer. `init/1` receives the hephaestus module name and calls `Instances.register/1`.
- When the process dies (supervisor shutdown, crash), Registry automatically deregisters — no `terminate/1` needed.
- `start_link/1` accepts the module atom.

### Application integration

The `Hephaestus.Instances` registry must start in the `Hephaestus.Application`. Read `lib/hephaestus/application.ex` — it already exists but has an empty children list. Add `Hephaestus.Instances` to it.

**Note:** Do NOT modify `lib/hephaestus.ex` in this task. The Tracker is added to the supervision tree in task-008.

## Done when

- [ ] `Hephaestus.Instances` can be started as a supervisor child
- [ ] `Tracker.start_link(MyModule)` registers the module
- [ ] `lookup!/0` returns the registered module when exactly one exists
- [ ] `lookup!/0` raises with clear message when none registered
- [ ] `lookup!/0` raises with module list when multiple registered
- [ ] Killing the Tracker process deregisters the module (Registry cleanup)
- [ ] `Hephaestus.Application` starts the Instances registry
- [ ] All tests pass
