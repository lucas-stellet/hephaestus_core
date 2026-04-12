# CLAUDE.md

## Changelog

This project maintains a `CHANGELOG.md` following the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

When making changes, update `CHANGELOG.md` under an `[Unreleased]` section. On version bumps, move unreleased entries under the new version heading with the release date.

The changelog is registered as an ExDoc extra in `mix.exs` and appears in the generated documentation sidebar.

## Hephaestus Ecosystem — Migration Guide

hephaestus_core itself has no database tables. The extensions `hephaestus_ecto` and `hephaestus_oban` ship versioned migrations that host applications must run via Ecto.

### Architecture

Both extensions follow the **Oban migration pattern**:

- Versioned migration modules (`V01`, `V02`, ...) live under `lib/<pkg>/migrations/postgres/`.
- An orchestrator (`lib/<pkg>/migrations/postgres.ex`) applies only the versions not yet run.
- The applied schema version is stored as a **PostgreSQL table comment** on the managed table (`workflow_instances` for ecto, `hephaestus_step_results` for oban).
- All DDL operations use idempotent helpers (`create_if_not_exists`, `add_if_not_exists`, etc.) so re-running migrations is safe.

### How host applications create migrations

Generate one Ecto migration per extension:

```elixir
# priv/repo/migrations/20240101000001_create_workflow_instances.exs
defmodule MyApp.Repo.Migrations.CreateWorkflowInstances do
  use Ecto.Migration

  def up, do: HephaestusEcto.Migration.up()
  def down, do: HephaestusEcto.Migration.down()
end

# priv/repo/migrations/20240101000002_create_hephaestus_step_results.exs
defmodule MyApp.Repo.Migrations.CreateHephaestusStepResults do
  use Ecto.Migration

  def up, do: HephaestusOban.Migration.up()
  def down, do: HephaestusOban.Migration.down()
end
```

**Order matters**: ecto migration must run before oban (foreign key dependency).

### Upgrading when extensions add new schema versions

When a new extension release ships a new migration version, create a **new** Ecto migration in the host app:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeHephaestusEcto do
  use Ecto.Migration

  def up, do: HephaestusEcto.Migration.up()    # runs only missing versions
  def down, do: HephaestusEcto.Migration.down() # rolls back to initial
end
```

You do **not** need `@disable_ddl_transaction` or `@disable_migration_lock` — the migrations are designed to run within standard Ecto DDL transactions.

### Caveats

1. **Do not manually alter lib-managed tables.** If you need a column that the lib doesn't provide, add it in a separate migration on a separate table or talk to the lib maintainers.

2. **Lost table comments.** If you restore from a backup that strips table comments, `migrated_version()` returns 0 and `up()` will re-run all versions. This is safe because all operations are idempotent. You can also manually fix: `COMMENT ON TABLE "public".workflow_instances IS '2'`.

3. **Multi-tenant / prefix support.** Both extensions accept a `:prefix` option for PostgreSQL schema isolation:
   ```elixir
   def up, do: HephaestusEcto.Migration.up(prefix: "tenant_a")
   ```

4. **Check current version.** Use `HephaestusEcto.Migration.migrated_version()` or `HephaestusOban.Migration.migrated_version()` to inspect the applied schema version.

5. **Advisory locks.** For production deployments with multiple nodes, configure your Repo to use advisory locks:
   ```elixir
   config MyApp.Repo, migration_lock: :pg_advisory_lock
   ```
   This prevents concurrent migration attempts from conflicting. See the [safe-ecto-migrations guide](https://github.com/fly-apps/safe-ecto-migrations) for details.

### Business Keys and Workflow Identity (0.3.0+)

Every workflow must declare a business key via the `:unique` option:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow,
    unique: [key: "orderid"]
end
```

**Key rules:**
- `key` format: lowercase letters and numbers only (`[a-z0-9]+`)
- Instance IDs are composite: `"key::value"` (e.g., `"orderid::abc123"`)
- Values: `[a-z0-9]+` or valid UUIDs (hyphens only in UUID format)
- `::` is a reserved separator

**Uniqueness scopes:**
- `:workflow` (default) — one active instance per ID per workflow module
- `:version` — one per ID per workflow version (allows V1 and V2 to coexist)
- `:global` — one per ID across all workflows
- `:none` — business key for identity, no uniqueness constraint

**Workflow facade:** Workflows generate `start/2`, `resume/2`, `get/1`, `list/1`, `cancel/1`:

```elixir
{:ok, id} = OrderFlow.start("abc123", %{amount: 100})
:ok = OrderFlow.resume("abc123", :payment_confirmed)
{:ok, instance} = OrderFlow.get("abc123")
```

**Auto-discovery:** The Hephaestus module registers itself at boot via `Hephaestus.Instances`. Workflows find it automatically. For the rare case of multiple Hephaestus instances, pass `hephaestus: MyApp.Hephaestus` in the workflow's `use` options.

**`start_instance` requires `id:`:**

```elixir
{:ok, id} = MyApp.Hephaestus.start_instance(OrderFlow, %{amount: 100}, id: "orderid::abc123")
```

### Adding a new migration version to the extensions

When developing a new schema change for hephaestus_ecto or hephaestus_oban:

1. Create a new `VNN.ex` module under `lib/<pkg>/migrations/postgres/`.
2. Bump `@current_version` in the orchestrator (`lib/<pkg>/migrations/postgres.ex`).
3. Use idempotent operations: `add_if_not_exists`, `create_if_not_exists`, `drop_if_exists`, `remove_if_exists`.
4. Accept `%{prefix: prefix}` (and `quoted_prefix` if you need quoted SQL identifiers) in `up/1` and `down/1`.
5. Add a test in `test/<pkg>/migrations/postgres_test.exs`.
6. Update `CHANGELOG.md`.
