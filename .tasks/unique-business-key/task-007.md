# Task 007: Add `unique` option to Workflow DSL + generate `__unique__/0`

**Wave**: 2 | **Effort**: M
**Depends on**: task-001
**Blocks**: task-010

## Objective

Extend the `use Hephaestus.Workflow` macro to accept the mandatory `:unique` option and generate the `__unique__/0` introspection function. This task handles DSL parsing and compile-time validation only — facade function generation is task-010.

## Files

**Modify:** `lib/hephaestus/core/workflow.ex` — add unique option handling
**Create:** `test/hephaestus/core/workflow_unique_test.exs` — tests for unique DSL

**Read:** `lib/hephaestus/core/workflow/unique.ex` — the Unique struct (from task-001)

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

## Done when

- [ ] `use Hephaestus.Workflow, unique: [key: "orderid"]` compiles and generates `__unique__/0`
- [ ] `__unique__/0` returns `%Hephaestus.Workflow.Unique{key: "orderid", scope: :workflow}`
- [ ] `use Hephaestus.Workflow` without `unique:` raises CompileError
- [ ] Invalid unique config raises at compile time
- [ ] `use Hephaestus.Workflow, unique: [...], hephaestus: MyModule` generates `__hephaestus__/0`
- [ ] Works for both umbrella and standalone workflows
- [ ] All new tests pass
