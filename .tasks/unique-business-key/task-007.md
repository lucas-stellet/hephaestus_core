# Task 007: Add `unique` option to Workflow DSL + generate `__unique__/0`

**Wave**: 2 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-010

## Objective

Extend the `use Hephaestus.Workflow` macro to accept the mandatory `:unique` option and generate the `__unique__/0` introspection function. This task handles DSL parsing and compile-time validation only — facade function generation is task-010.

## Files

**Create:** `test/hephaestus/core/workflow_unique_test.exs` — tests for unique DSL
**Modify:** `lib/hephaestus/core/workflow.ex` — add unique option handling

**Read:** `lib/hephaestus/core/workflow/unique.ex` — the Unique struct (from task-001)

## TDD Execution Order

### Phase 1: RED — Write compile-time tests first

Create the test file using `Code.compile_quoted` to test inline workflow definitions (same pattern as `workflow_tags_test.exs`). Tests will fail because the macro doesn't handle `unique:` yet.

### Phase 2: GREEN — Add unique handling to macro

### Phase 3: REFACTOR — Clean up if needed

**Important:** Do NOT update existing test workflow fixtures. They will break because they lack `unique:`. Task-011 handles that.

## Requirements

### In `__using__/1` macro

Add `@hephaestus_unique` module attribute from opts:

```elixir
@hephaestus_unique Keyword.get(opts, :unique, nil)
```

### In `__before_compile__` — both umbrella and standard paths

1. Read `@hephaestus_unique`
2. If nil, raise `CompileError` with message: "the :unique option is required for Hephaestus.Workflow"
3. If present, call `Hephaestus.Workflow.Unique.new!(unique_opts)` to validate
4. Generate `__unique__/0` that returns the validated struct

For **umbrella** workflows (`__before_compile_umbrella__`):
```elixir
# Add to the generated quote block
@doc false
def __unique__, do: unquote(Macro.escape(unique_struct))
```

For **standard** workflows (`__before_compile_standard__`):
```elixir
# Same pattern
@doc false
def __unique__, do: unquote(Macro.escape(unique_struct))
```

### Also accept `:hephaestus` option

For the rare multi-instance case, accept `hephaestus: MyApp.Hephaestus` in opts. Store as `@hephaestus_instance` module attribute. Generate `__hephaestus__/0` that returns the module or `nil`.

```elixir
@hephaestus_instance Keyword.get(opts, :hephaestus, nil)

# Generated:
@doc false
def __hephaestus__, do: unquote(hephaestus_instance)
```

### Compile-time errors

- Missing `unique` → `CompileError`: "the :unique option is required for Hephaestus.Workflow"
- Invalid unique config → `ArgumentError` from `Unique.new!/1` (already implemented in task-001)

### Important

Do NOT update existing test workflow fixtures in this task. They will break compilation because they don't have `unique:`. That's expected — task-011 updates all test fixtures. For THIS task's tests, create new test workflow modules in the test file itself.

## TDD Test Sequence

**Test file:** `test/hephaestus/core/workflow_unique_test.exs`

```elixir
defmodule Hephaestus.Core.WorkflowUniqueTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Workflow.Unique

  describe "__unique__/0 for standalone workflow" do
    test "returns Unique struct with configured key and default scope" do
      # Arrange — compile a test workflow inline
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueStandalone do
              use Hephaestus.Workflow, unique: [key: "orderid"]

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      # Act
      unique = module.__unique__()

      # Assert
      assert %Unique{key: "orderid", scope: :workflow} = unique
    end

    test "returns Unique struct with explicit scope" do
      # Arrange
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueScopeGlobal do
              use Hephaestus.Workflow, unique: [key: "companyid", scope: :global]

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      # Act
      unique = module.__unique__()

      # Assert
      assert %Unique{key: "companyid", scope: :global} = unique
    end
  end

  describe "__hephaestus__/0" do
    test "returns nil when not configured" do
      # Arrange
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueNoHeph do
              use Hephaestus.Workflow, unique: [key: "testid"]

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      # Act / Assert
      assert module.__hephaestus__() == nil
    end

    test "returns configured module when set" do
      # Arrange
      [{module, _}] =
        Code.compile_quoted(
          quote do
            defmodule TestUniqueWithHeph do
              use Hephaestus.Workflow,
                unique: [key: "testid"],
                hephaestus: MyApp.CustomHephaestus

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )

      # Act / Assert
      assert module.__hephaestus__() == MyApp.CustomHephaestus
    end
  end

  describe "compile-time validation" do
    test "raises CompileError when unique is not provided" do
      # Arrange / Act / Assert
      assert_raise CompileError, ~r/the :unique option is required/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestNoUnique do
              use Hephaestus.Workflow

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )
      end
    end

    test "raises ArgumentError for invalid unique key" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/unique key must contain only lowercase/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestBadKey do
              use Hephaestus.Workflow, unique: [key: "Bad-Key"]

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )
      end
    end

    test "raises ArgumentError for invalid scope" do
      # Arrange / Act / Assert
      assert_raise ArgumentError, ~r/unique scope must be one of/, fn ->
        Code.compile_quoted(
          quote do
            defmodule TestBadScope do
              use Hephaestus.Workflow, unique: [key: "ok", scope: :nope]

              @impl true
              def start, do: Hephaestus.Steps.Done

              @impl true
              def transit(Hephaestus.Steps.Done, :done, _ctx), do: Hephaestus.Steps.Done
            end
          end
        )
      end
    end
  end
end
```

## Done when

- [ ] All 6 tests pass
- [ ] No compilation warnings
- [ ] `mix test test/hephaestus/core/workflow_unique_test.exs` green
