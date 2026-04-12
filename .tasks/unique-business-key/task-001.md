# Task 001: Create `Hephaestus.Workflow.Unique` struct with validations

**Wave**: 0 | **Effort**: S
**Depends on**: none
**Blocks**: task-004, task-005, task-006, task-007

## Objective

Create the `Hephaestus.Workflow.Unique` struct that holds business key configuration for workflows. Includes `new!/1` constructor with compile-time validations.

## Files

**Create:** `lib/hephaestus/core/workflow/unique.ex` — the Unique struct module
**Create:** `test/hephaestus/core/workflow/unique_test.exs` — validation tests

## Requirements

The struct has two fields:
- `key` (required, string) — business key prefix. Format: `[a-z0-9]+` only. No hyphens, underscores, uppercase.
- `scope` (optional, atom, default `:workflow`) — one of `:workflow`, `:version`, `:global`, `:none`

Implement `new!/1` that accepts a keyword list, creates the struct via `struct!/2`, and validates:
- `key` is a string matching `~r/^[a-z0-9]+$/`
- `key` is not a non-string type (raise "unique key must be a string, got: ...")
- `scope` is one of the valid values
- Missing `key` triggers the standard `struct!` error

All validations raise `ArgumentError` with descriptive messages. This constructor will be called at compile-time by the Workflow macro.

Include `@type t`, `@type scope`, `@enforce_keys [:key]`.

## Done when

- [ ] `Unique.new!(key: "blueprintid")` returns `%Unique{key: "blueprintid", scope: :workflow}`
- [ ] `Unique.new!(key: "blueprintid", scope: :global)` works
- [ ] `Unique.new!(key: "Blueprint")` raises with clear message about format
- [ ] `Unique.new!(key: 123)` raises about string type
- [ ] `Unique.new!(scope: :workflow)` raises about missing key
- [ ] `Unique.new!(key: "ok", scope: :invalid)` raises about valid scopes
- [ ] All tests pass
