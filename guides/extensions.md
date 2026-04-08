# Extensions

Hephaestus is modular by design. The core package provides the workflow engine
with in-memory storage (ETS) and local execution (GenServer per instance) — enough
to develop, test, and run single-node deployments. Extension packages plug into
the same adapter contracts to add production capabilities without changing your
workflow definitions or step implementations.

This guide explains what each extension does, when to use it, and how to set it up.

## Choosing the right stack

| You need... | Packages | Why |
|---|---|---|
| Prototyping, tests, single-node | `hephaestus` | ETS storage + local runner. Zero external deps. |
| Workflows that survive restarts | `hephaestus` + `hephaestus_ecto` | Ecto adapter persists instances as JSONB in PostgreSQL. |
| Distributed execution, retries, job queues | `hephaestus` + `hephaestus_ecto` + `hephaestus_oban` | Oban runner replaces GenServer with durable, retryable jobs. |
| Full production stack | All three + built-in telemetry | Persistent, distributed, observable workflows. |

Start with core alone during development. Add extensions as your requirements
grow — each one is a dependency swap, not a rewrite.

## hephaestus_ecto

Ecto/PostgreSQL storage adapter. Replaces the built-in ETS storage with a single
`workflow_instances` table backed by JSONB and GIN indexing.

### What it provides

- **`HephaestusEcto.Storage`** — implements the `Hephaestus.Runtime.Storage`
  behaviour (`get/1`, `put/1`, `delete/1`, `query/1`).
- **Migration generator** — `mix hephaestus_ecto.gen.migration` creates the
  `workflow_instances` table with UUID primary key, B-tree indexes on `workflow`
  and `status`, and a GIN index (`jsonb_path_ops`) on the `state` JSONB column.
- **Serializer** — handles round-trip conversion between Elixir types (atoms,
  MapSets, DateTime) and JSONB-safe representations. Deserialization uses
  `String.to_existing_atom/1` — no arbitrary atom creation from database values.
- **Named instances** — multiple storage instances can coexist for multi-tenant
  setups.

### When to use

- Your workflows must survive VM restarts or deployments.
- You need to query workflow state from outside the running application (admin
  dashboards, reporting, debugging).
- You're running multiple nodes and need a shared persistence layer.

### Setup

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:hephaestus, "~> 0.1.3"},
    {:hephaestus_ecto, "~> 0.1.0"}
  ]
end
```

Generate and run the migration:

```bash
mix hephaestus_ecto.gen.migration
mix ecto.migrate
```

Configure your engine module to use Ecto storage:

```elixir
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
    runner: Hephaestus.Runtime.Runner.Local
end
```

Everything else stays the same — your workflows, steps, and supervision tree
don't change. Instances are now persisted to PostgreSQL instead of ETS.

### Querying instances

The storage adapter supports filtering by status and workflow:

```elixir
HephaestusEcto.Storage.query(status: :running)
HephaestusEcto.Storage.query(workflow: MyApp.OrderWorkflow)
HephaestusEcto.Storage.query(status: :waiting, workflow: MyApp.PaymentWorkflow)
```

For advanced queries against the JSONB `state` column, use Ecto directly:

```elixir
import Ecto.Query

from(i in HephaestusEcto.Schema.Instance,
  where: fragment("state @> ?", ^%{"context" => %{"initial" => %{"order_id" => 123}}})
)
|> MyApp.Repo.all()
```

### Requirements

- PostgreSQL 9.4+ (JSONB and GIN indexes)
- Ecto SQL ~> 3.10

## hephaestus_oban

Oban-based runner adapter. Replaces the built-in local runner (one GenServer per
instance) with durable Oban jobs. Brings distributed execution, persistent job
queues, automatic retries with backoff, and advisory-lock-based concurrency
control.

**Requires `hephaestus_ecto`** — the Oban runner persists instances through the
Ecto storage adapter.

### What it provides

- **`HephaestusOban.Runner`** — implements the `Hephaestus.Runtime.Runner`
  behaviour using three Oban workers.
- **Three-worker architecture**:

  | Worker | Role | Writes to Instance? |
  |--------|------|---------------------|
  | **AdvanceWorker** | Orchestrator. Reads step results, applies engine transitions, persists the instance. Serialized per instance via Oban unique + `pg_advisory_xact_lock`. | Yes (single writer) |
  | **ExecuteStepWorker** | Executes a single step. Writes result to `step_results` table, enqueues AdvanceWorker. Idempotent via existence check. | No |
  | **ResumeWorker** | Handles external events and durable timers. Writes to `step_results`, enqueues AdvanceWorker. | No |

- **Zero-contention fan-out** — during parallel execution, each step worker
  writes to an auxiliary `hephaestus_step_results` table instead of the instance
  directly. The AdvanceWorker is the single writer, serialized via advisory lock.
- **Failure handling** — when a step exhausts all retries, the `FailureHandler`
  telemetry listener marks the workflow as `:failed` and cancels remaining jobs.
- **Durable timers** — `schedule_resume/3` creates an Oban job that survives VM
  restarts, unlike the local runner's process-local timers.
- **Job observability** — automatically populates Oban job `meta` and `tags`
  from the workflow's `__tags__/0` and `__metadata__/0` (declared via
  `use Hephaestus.Workflow, tags: [...], metadata: %{...}`). Enables filtering
  in Oban Web by workflow type, instance ID, step name, or custom labels.
- **Retry configuration** — resolves with most-specific-wins priority:
  1. `Step.retry_config/0` (per-step override)
  2. `Workflow.default_retry_config/0` (per-workflow default)
  3. Library default: `%{max_attempts: 5, backoff: :exponential, max_backoff: 60_000}`

### When to use

- You need workflows to execute across multiple nodes (distributed).
- Steps must retry automatically on failure with configurable backoff.
- You need durable timers that survive deployments.
- You want Oban's job management UI (Oban Web) for monitoring workflow execution.

### Setup

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:hephaestus, "~> 0.1.3"},
    {:hephaestus_ecto, "~> 0.1.0"},
    {:hephaestus_oban, "~> 0.1.0"}
  ]
end
```

Generate and run both migrations (Ecto migration must come first):

```bash
mix hephaestus_ecto.gen.migration
mix hephaestus_oban.gen.migration
mix ecto.migrate
```

Configure your engine module:

```elixir
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
    runner: {HephaestusOban.Runner, oban: MyApp.Oban}
end
```

Set up your supervision tree:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, name: MyApp.Oban, repo: MyApp.Repo, queues: [hephaestus: 10]},
    MyApp.Hephaestus
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

The `hephaestus: 10` queue configuration means up to 10 Oban jobs run
concurrently. In a fan-out of 20 steps, only 10 execute at once — the rest wait
in the queue. Adjust based on your workload.

For fine-grained control, use separate queues for orchestration and execution:

```elixir
{Oban, queues: [hephaestus_advance: 5, hephaestus_execute: 20]}
```

### Requirements

- Oban >= 2.14
- PostgreSQL (advisory locks and JSONB)
- `hephaestus_ecto` ~> 0.1.0

## Combining extensions

The typical production stack uses both extensions together. Here's a
complete setup:

```elixir
# mix.exs
def deps do
  [
    {:hephaestus, "~> 0.1.5"},
    {:hephaestus_ecto, "~> 0.1.0"},
    {:hephaestus_oban, "~> 0.1.0"}
  ]
end
```

```elixir
# lib/my_app/hephaestus.ex
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
    runner: {HephaestusOban.Runner, oban: MyApp.Oban}
end
```

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  # Telemetry is built-in — just attach the log handler
  Hephaestus.Telemetry.LogHandler.attach()

  children = [
    MyApp.Repo,
    {Oban, name: MyApp.Oban, repo: MyApp.Repo, queues: [hephaestus: 10]},
    MyApp.Hephaestus
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Your workflows and steps remain identical to the core-only version. The only
change is the adapter configuration in `use Hephaestus` and the supervision tree.

## Migration path

Hephaestus is designed to grow with your application:

1. **Start with core alone.** Use ETS storage and the local runner during
   development and testing. No database, no external dependencies. Focus on
   getting your workflow logic right.

2. **Add Ecto when you need persistence.** When workflows must survive restarts
   or you need to query state externally, add `hephaestus_ecto`. Swap the storage
   adapter — everything else stays the same.

3. **Add Oban when you need distribution.** When you deploy to multiple nodes or
   need automatic retries and durable timers, add `hephaestus_oban`. Swap the
   runner adapter.

4. **Enable telemetry when you need observability.** Telemetry is built into the
   core since 0.1.5. Just call `Hephaestus.Telemetry.LogHandler.attach()` in
   your application startup for structured logs, or plug
   `Hephaestus.Telemetry.Metrics.metrics()` into your reporter for dashboards.

Each step is additive. You never need to rewrite workflows or steps — the adapter
pattern ensures that the runtime changes underneath while your business logic
stays exactly the same.
