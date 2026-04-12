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

## TDD Test Sequence

**Test file:** `test/hephaestus/instances_test.exs`

```elixir
defmodule Hephaestus.InstancesTest do
  use ExUnit.Case, async: false

  alias Hephaestus.Instances
  alias Hephaestus.Instances.Tracker

  setup do
    # Ensure a clean registry for each test.
    # The Application starts Hephaestus.Instances globally,
    # so we need to clean up any registrations between tests.
    on_exit(fn ->
      # Kill any tracker processes that may be lingering
      for {pid, _} <- Registry.lookup(Hephaestus.Instances.Registry, :_) do
        Process.exit(pid, :kill)
      end
      Process.sleep(10)
    end)

    :ok
  end

  describe "lookup!/0 with no registrations" do
    test "raises when no Hephaestus instance is registered" do
      # Arrange — nothing registered

      # Act / Assert
      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end
  end

  describe "Tracker registration" do
    test "registers module on start_link" do
      # Arrange
      {:ok, _pid} = Tracker.start_link(MyApp.TestHephaestus)

      # Act
      result = Instances.lookup!()

      # Assert
      assert result == MyApp.TestHephaestus
    end
  end

  describe "lookup!/0 with single registration" do
    test "returns the registered module" do
      # Arrange
      {:ok, _pid} = Tracker.start_link(MyApp.SingleInstance)

      # Act
      module = Instances.lookup!()

      # Assert
      assert module == MyApp.SingleInstance
    end
  end

  describe "lookup!/0 with multiple registrations" do
    test "raises listing all registered modules" do
      # Arrange
      {:ok, _pid1} = Tracker.start_link(MyApp.InstanceA)
      {:ok, _pid2} = Tracker.start_link(MyApp.InstanceB)

      # Act / Assert
      assert_raise RuntimeError, ~r/Multiple Hephaestus instances/, fn ->
        Instances.lookup!()
      end
    end
  end

  describe "auto-deregistration" do
    test "deregisters when tracker process is killed" do
      # Arrange
      {:ok, pid} = Tracker.start_link(MyApp.Ephemeral)
      assert Instances.lookup!() == MyApp.Ephemeral

      # Act
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Assert
      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end

    test "deregisters when tracker process stops normally" do
      # Arrange
      {:ok, pid} = Tracker.start_link(MyApp.Graceful)
      assert Instances.lookup!() == MyApp.Graceful

      # Act
      GenServer.stop(pid, :normal)
      Process.sleep(50)

      # Assert
      assert_raise RuntimeError, ~r/No Hephaestus instance running/, fn ->
        Instances.lookup!()
      end
    end
  end
end
```

## Done when

- [ ] All 6 tests pass
- [ ] `Hephaestus.Application` starts the Instances registry
- [ ] No compilation warnings
- [ ] `mix test test/hephaestus/instances_test.exs` green
