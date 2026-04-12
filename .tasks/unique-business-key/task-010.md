# Task 010: Generate facade functions in Workflow macro

**Wave**: 3 | **Effort**: L
**Depends on**: task-006, task-007, task-008
**Blocks**: task-011

## Objective

The most complex task. Extend the Workflow macro to generate facade functions (`start/2`, `resume/2`, `get/1`, `list/1`, `cancel/1`) in umbrella and standalone workflow modules. These functions construct the composite ID via `Hephaestus.Uniqueness` and delegate to the Hephaestus module discovered via `Hephaestus.Instances`.

## Files

**Create:** `test/hephaestus/core/workflow_facade_test.exs` — comprehensive facade tests first
**Modify:** `lib/hephaestus/core/workflow.ex` — add facade generation in both umbrella and standard compile paths

**Read:** `lib/hephaestus/uniqueness.ex` — Uniqueness module
**Read:** `lib/hephaestus/instances.ex` — Instances registry
**Read:** `lib/hephaestus/core/workflow/unique.ex` — Unique struct

## TDD Execution Order

### Phase 1: RED — Write full facade test suite first

Create test file with inline test workflows (WITH `unique:`) and tests for all facade functions. Define test support workflows for the facade tests. Tests fail because facade functions aren't generated yet.

### Phase 2: GREEN — Generate facade functions in macro

Implement facade generation in both `__before_compile_umbrella__` and `__before_compile_standard__`. Work through tests one describe block at a time: start → resume → get → list → cancel → scope:none.

### Phase 3: REFACTOR — Extract shared logic between umbrella/standard paths

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

## TDD Test Sequence

**Test file:** `test/hephaestus/core/workflow_facade_test.exs`

This test requires a running Hephaestus supervision tree. Use `Hephaestus.Test.Hephaestus` (started in test setup). Define inline test workflows with `unique:`.

```elixir
defmodule Hephaestus.Core.WorkflowFacadeTest do
  use ExUnit.Case, async: false

  # Test workflows defined inline — these need unique: and proper steps
  # They are defined in test/support/ or inline via Code.compile_quoted

  describe "start/2" do
    test "creates instance with composite ID" do
      # Arrange — workflow with unique: [key: "facadetest"]
      # Act
      {:ok, id} = TestFacadeWorkflow.start("abc123", %{data: true})

      # Assert
      assert id == "facadetest::abc123"
    end

    test "rejects duplicate when scope is :workflow" do
      # Arrange
      {:ok, _} = TestFacadeWorkflow.start("dup1", %{})

      # Act
      result = TestFacadeWorkflow.start("dup1", %{})

      # Assert
      assert result == {:error, :already_running}
    end

    test "validates value format" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/invalid id value/, fn ->
        TestFacadeWorkflow.start("INVALID", %{})
      end
    end
  end

  describe "resume/2" do
    test "resumes instance by business value" do
      # Arrange — start a workflow that waits for event
      {:ok, _id} = TestFacadeEventWorkflow.start("res1", %{})
      Process.sleep(50)  # let it advance to waiting

      # Act
      result = TestFacadeEventWorkflow.resume("res1", :payment_confirmed)

      # Assert
      assert result == :ok
    end
  end

  describe "get/1" do
    test "returns instance by business value" do
      # Arrange
      {:ok, _} = TestFacadeWorkflow.start("get1", %{data: 42})

      # Act
      result = TestFacadeWorkflow.get("get1")

      # Assert
      assert {:ok, instance} = result
      assert instance.id == "facadetest::get1"
      assert instance.context.initial == %{data: 42}
    end

    test "returns {:error, :not_found} for unknown value" do
      # Arrange / Act
      result = TestFacadeWorkflow.get("nonexistent")

      # Assert
      assert result == {:error, :not_found}
    end
  end

  describe "list/1" do
    test "returns all instances for the workflow" do
      # Arrange
      {:ok, _} = TestFacadeWorkflow.start("list1", %{})
      {:ok, _} = TestFacadeWorkflow.start("list2", %{})

      # Act
      results = TestFacadeWorkflow.list()

      # Assert
      ids = Enum.map(results, & &1.id)
      assert "facadetest::list1" in ids
      assert "facadetest::list2" in ids
    end

    test "accepts additional filters" do
      # Arrange
      {:ok, _} = TestFacadeWorkflow.start("listf1", %{})

      # Act
      results = TestFacadeWorkflow.list(status: :pending)

      # Assert
      assert Enum.all?(results, & &1.status == :pending)
    end
  end

  describe "cancel/1" do
    test "cancels an active instance" do
      # Arrange — start a workflow that will be in waiting state
      {:ok, _} = TestFacadeEventWorkflow.start("cancel1", %{})
      Process.sleep(50)

      # Act
      result = TestFacadeEventWorkflow.cancel("cancel1")

      # Assert
      assert result == :ok
      {:ok, instance} = TestFacadeEventWorkflow.get("cancel1")
      assert instance.status == :cancelled
    end

    test "returns {:error, :not_found} for unknown value" do
      # Arrange / Act
      result = TestFacadeWorkflow.cancel("nocancel")

      # Assert
      assert result == {:error, :not_found}
    end
  end

  describe "scope :none" do
    test "start/2 creates instance with suffixed ID" do
      # Arrange — workflow with unique: [key: "noneid", scope: :none]

      # Act
      {:ok, id} = TestFacadeNoneWorkflow.start("abc123", %{})

      # Assert
      assert String.starts_with?(id, "noneid::abc123::")
    end

    test "resume/2 is not defined" do
      # Arrange / Act / Assert
      refute function_exported?(TestFacadeNoneWorkflow, :resume, 2)
    end

    test "get/1 is not defined" do
      # Arrange / Act / Assert
      refute function_exported?(TestFacadeNoneWorkflow, :get, 1)
    end

    test "cancel/1 is not defined" do
      # Arrange / Act / Assert
      refute function_exported?(TestFacadeNoneWorkflow, :cancel, 1)
    end

    test "list/1 is defined" do
      # Arrange / Act / Assert
      assert function_exported?(TestFacadeNoneWorkflow, :list, 0)
      assert function_exported?(TestFacadeNoneWorkflow, :list, 1)
    end
  end
end
```

## Done when

- [ ] All 14 tests pass
- [ ] Facade functions generated correctly for all scopes
- [ ] `scope: :none` only generates `start/2` and `list/1`
- [ ] `mix test test/hephaestus/core/workflow_facade_test.exs` green
