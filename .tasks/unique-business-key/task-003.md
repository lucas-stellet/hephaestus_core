# Task 003: Create `Hephaestus.Instances` registry + Tracker

**Wave**: 0 | **Effort**: M
**Depends on**: none
**Blocks**: task-008, task-010

## Objective

Create the auto-discovery mechanism that allows workflow facades to find the Hephaestus module without explicit configuration. Uses Elixir's `Registry` (same pattern as Oban).

## Files

**Create:** `test/hephaestus/instances_test.exs` — tests for register, lookup, multi-instance error
**Create:** `lib/hephaestus/instances.ex` — registry module with `register/1` and `lookup!/0`
**Create:** `lib/hephaestus/instances/tracker.ex` — GenServer that registers on init, auto-deregisters on death

## TDD Execution Order

### Phase 1: RED — Write all tests first

Create the test file. Create minimal module stubs for `Hephaestus.Instances` and `Hephaestus.Instances.Tracker` so tests compile. The Instances registry needs to be started before tests run — add `Hephaestus.Instances` to `Hephaestus.Application` children first (it already exists with empty children list).

### Phase 2: GREEN — Implement to make tests pass

- `Hephaestus.Instances.child_spec/1` — `Registry` child spec with `keys: :unique`, name `Hephaestus.Instances.Registry`
- `Hephaestus.Instances.register/1` — registers module in the registry
- `Hephaestus.Instances.lookup!/0` — returns single registered module, raises if none or multiple
- `Hephaestus.Instances.Tracker` — GenServer, `init/1` calls `register/1`, auto-deregisters on death via Registry cleanup
- Add `Hephaestus.Instances` to `Hephaestus.Application` children

**Note:** Do NOT modify `lib/hephaestus.ex`. The Tracker is added to the supervision tree in task-008.

### Phase 3: REFACTOR — Clean up if needed

## Tests

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
