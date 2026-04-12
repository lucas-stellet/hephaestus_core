# Task 002: Create `Hephaestus.Uniqueness` module (ID build, validate, extract)

**Wave**: 0 | **Effort**: M
**Depends on**: none
**Blocks**: task-006, task-010

## Objective

Create the `Hephaestus.Uniqueness` module that handles composite ID construction, value validation, and value extraction. This task does NOT include `check/5` (that's task-006).

## Files

**Create:** `lib/hephaestus/uniqueness.ex` — the Uniqueness module
**Create:** `test/hephaestus/uniqueness_test.exs` — tests for build/validate/extract

## Requirements

### `build_id/2`

Takes a `%Unique{}` struct and a value string. Returns `"key::value"`.

```elixir
def build_id(%Unique{key: key}, value) do
  validate_value!(value)
  "#{key}::#{value}"
end
```

### `build_id_with_suffix/2`

For `scope: :none` — appends a random 8-char hex suffix to avoid storage collision.

```elixir
def build_id_with_suffix(%Unique{key: key}, value) do
  validate_value!(value)
  suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  "#{key}::#{value}::#{suffix}"
end
```

### `validate_value!/1`

Value must be either:
- Simple: `[a-z0-9]+` (lowercase alphanumeric only)
- UUID: `[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`

The `-` character is ONLY permitted inside valid UUIDs. `"abc-123"` is invalid. `"550e8400-e29b-41d4-a716-446655440000"` is valid.

Raises `ArgumentError` with: `"invalid id value: #{inspect(value)}. Must be [a-z0-9]+ or a valid UUID"`

### `extract_value/1`

Extracts the business value from a composite ID:
- `"blueprintid::abc123"` -> `"abc123"`
- `"userid::abc123::r7x9k2"` -> `"abc123"` (strips suffix for scope :none IDs)

Raises `ArgumentError` for malformed IDs.

## Done when

- [ ] `build_id(%Unique{key: "bp"}, "abc123")` returns `"bp::abc123"`
- [ ] `build_id_with_suffix` returns `"key::value::8hexchars"` format
- [ ] `validate_value!("abc123")` passes
- [ ] `validate_value!("550e8400-e29b-41d4-a716-446655440000")` passes
- [ ] `validate_value!("ABC")` raises
- [ ] `validate_value!("abc-123")` raises (hyphen outside UUID)
- [ ] `validate_value!("abc_123")` raises
- [ ] `validate_value!("abc::123")` raises
- [ ] `extract_value("bp::abc123")` returns `"abc123"`
- [ ] `extract_value("bp::abc123::suffix")` returns `"abc123"`
- [ ] All tests pass
