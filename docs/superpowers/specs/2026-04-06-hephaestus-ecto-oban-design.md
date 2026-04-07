# Design Spec: hephaestus_ecto + hephaestus_oban

> Date: 2026-04-06
> Status: Approved
> Scope: Two new packages (hephaestus_ecto, hephaestus_oban) + minor changes to hephaestus_core

## Goals

- **Persistencia real**: workflows sobrevivem restart da VM via PostgreSQL
- **Adapters de producao**: preparar a lib pra publicacao no Hex.pm com adapters alem de ETS/Local
- **Backward compatible**: hephaestus_core continua funcionando sem as novas libs

## Non-Goals

- Dashboard/UI de workflows
- Execucao distribuida multi-node (beneficio colateral do Oban, mas nao e driver)
- Oban Pro (apenas Oban open-source)

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  Consumer App                                            │
│                                                          │
│  defmodule MyApp.Hephaestus do                           │
│    use Hephaestus,                                       │
│      storage: {HephaestusEcto.Storage, repo: MyApp.Repo},│
│      runner: {HephaestusOban.Runner, oban: MyApp.Oban}   │
│  end                                                     │
└────────────┬─────────────────────────┬───────────────────┘
             │                         │
     ┌───────▼───────┐       ┌────────▼────────┐
     │hephaestus_ecto│       │ hephaestus_oban  │
     │               │       │                  │
     │ Storage impl  │◄──────│ Runner impl      │
     │ Ecto + PG     │       │ 3 Oban workers   │
     │ Serializer    │       │ step_results tbl  │
     │ Migration gen │       │ Telemetry handler │
     └───────┬───────┘       │ Migration gen     │
             │               └────────┬─────────┘
     ┌───────▼────────────────────────▼─────────┐
     │          hephaestus_core                  │
     │                                           │
     │  Storage behaviour    Runner behaviour    │
     │  Engine (pure)        Workflow macro       │
     │  Instance, Context    Step behaviour       │
     └───────────────────────────────────────────┘
```

## Package Dependencies

```
hephaestus_core          (no new deps)
hephaestus_ecto          depends on: hephaestus_core, ecto_sql, postgrex
hephaestus_oban          depends on: hephaestus_core, hephaestus_ecto, oban >= 2.14
```

**Minimum Oban version:** 2.14+ required for `unique: [period: :infinity, states: [...]]` and stable `[:oban, :job, :stop]` telemetry with `:discard` state in metadata.

---

## Part 1: hephaestus_ecto

### 1.1 Responsibility

Ecto-backed storage adapter implementing `Hephaestus.Runtime.Storage`. Uses the consumer app's Repo — no internal Repo.

### 1.2 Database Schema

Single table, minimal columns + JSONB state field (schema minimo, opcao B).

```sql
CREATE TABLE workflow_instances (
  id          UUID PRIMARY KEY,
  workflow    VARCHAR(255) NOT NULL,
  status      VARCHAR(20)  NOT NULL DEFAULT 'pending',
  state       JSONB        NOT NULL DEFAULT '{}',
  inserted_at TIMESTAMP    NOT NULL,
  updated_at  TIMESTAMP    NOT NULL
);

CREATE INDEX idx_workflow_instances_status   ON workflow_instances (status);
CREATE INDEX idx_workflow_instances_workflow ON workflow_instances (workflow);
CREATE INDEX idx_workflow_instances_state    ON workflow_instances USING GIN (state jsonb_path_ops);
```

**Why JSONB + GIN jsonb_path_ops:**
- No extension needed — built-in since PostgreSQL 9.4
- Covers containment queries via `@>` operator (e.g., find instances with specific active step)
- ~3x smaller than default GIN jsonb_ops
- New Instance fields fall into `state` without migration
- Queries by `status` and `workflow` (the 90% case) use btree indexes on real columns

**The `state` field contains:**

```json
{
  "current_step": "Elixir.MyApp.Steps.Validate",
  "context": {
    "initial": {"order_id": 123},
    "steps": {"validate": {"valid": true}}
  },
  "step_configs": {},
  "active_steps": ["Elixir.MyApp.Steps.Pay"],
  "completed_steps": ["Elixir.MyApp.Steps.Validate"],
  "execution_history": [
    {
      "step_ref": "Elixir.MyApp.Steps.Validate",
      "event": "done",
      "timestamp": "2026-04-06T12:00:00Z"
    }
  ]
}
```

### 1.3 Ecto Schema

```elixir
defmodule HephaestusEcto.Schema.Instance do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "workflow_instances" do
    field :workflow, :string
    field :status, :string
    field :state, :map
    timestamps()
  end
end
```

### 1.4 Serialization

Module `HephaestusEcto.Serializer` handles bidirectional conversion:

**Instance.t() -> DB record:**
- Atoms to strings: `MyApp.Steps.Pay` -> `"Elixir.MyApp.Steps.Pay"`
- MapSets to sorted lists: `MapSet.new([:a, :b])` -> `["Elixir.A", "Elixir.B"]`
- Structs (Context, ExecutionEntry) to plain maps
- DateTime to ISO 8601 string

**DB record -> Instance.t():**
- Strings to atoms: `String.to_existing_atom/1` (safe — modules must be loaded)
- Lists to MapSets
- Maps to structs (Context, ExecutionEntry)
- ISO 8601 string to DateTime

### 1.5 Public API

`HephaestusEcto.Storage` is a plain module (no GenServer). Unlike `Storage.ETS` which needs a process to own the ETS table, Ecto repos are already process pools — wrapping them in a GenServer would add an unnecessary serialization bottleneck.

The repo reference is stored in a `:persistent_term` keyed by the storage name, set during `start_link/1` (called by the supervision tree).

```elixir
defmodule HephaestusEcto.Storage do
  @behaviour Hephaestus.Runtime.Storage

  # Called by supervision tree — stores repo in persistent_term, returns :ignore
  # opts: [repo: MyApp.Repo, name: __MODULE__]
  def start_link(opts)

  # Behaviour callbacks — arity-1 uses default name, arity-2 accepts name
  @impl Storage
  def get(instance_id)
  def get(name, instance_id)

  @impl Storage
  def put(instance)
  def put(name, instance)

  @impl Storage
  def delete(instance_id)
  def delete(name, instance_id)

  @impl Storage
  def query(filters)
  def query(name, filters)
end
```

`put/1,2` uses `Repo.insert/2` with `on_conflict: {:replace_all_except, [:inserted_at]}, conflict_target: :id` for upsert semantics that preserve the original creation timestamp.

`query/1,2` supports the same filters as Storage.ETS: `status:` and `workflow:`.

**Note on Storage behaviour arity mismatch:** The current `Storage` behaviour defines arity-1 callbacks, but `Runner.Local` calls storage via `apply(module, :put, [name, instance])` (arity-2). This is a pre-existing inconsistency in hephaestus_core. Both `Storage.ETS` and `HephaestusEcto.Storage` implement arity-1 (delegates to default name) and arity-2 (the real implementation). The `@impl` annotation applies to arity-1; arity-2 is an additional public function. A future core improvement could update the behaviour to formalize the arity-2 contract.

### 1.6 Migration Generator

```bash
mix hephaestus_ecto.gen.migration
```

Generates a migration file in the consumer app's `priv/repo/migrations/` directory. Pattern follows Oban's `mix oban.install`.

### 1.7 Consumer Usage

```elixir
# mix.exs
{:hephaestus_ecto, "~> 0.1"}

# Generate and run migration
$ mix hephaestus_ecto.gen.migration
$ mix ecto.migrate

# lib/my_app/hephaestus.ex
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
    runner: Hephaestus.Runtime.Runner.Local
end

# application.ex
children = [
  MyApp.Repo,
  MyApp.Hephaestus
]
```

### 1.8 Module Structure

```
lib/
  hephaestus_ecto/
    storage.ex           # @behaviour Storage implementation (plain module + persistent_term)
    schema/
      instance.ex        # Ecto schema for workflow_instances
    serializer.ex        # Instance.t() <-> DB record conversion
    migration.ex         # Migration module used by generator
mix/
  tasks/
    hephaestus_ecto.gen.migration.ex  # Mix task
```

---

## Part 2: hephaestus_oban

### 2.1 Responsibility

Oban-backed runner implementing `Hephaestus.Runtime.Runner`. Each step becomes an Oban job. Uses the consumer app's Oban instance — no internal Oban.

### 2.2 Worker Configuration Access

Oban workers are stateless — they only receive `%Oban.Job{args: ...}`. They need access to the Repo (for storage), the Oban instance name (for inserting new jobs), and the Storage name (for load/persist).

**Solution:** The `HephaestusOban.Runner` module stores config in `:persistent_term` during `start_link`, keyed by a config name derived from the entry module. Workers receive the config key in their job args and resolve everything from it.

```elixir
# At startup (called from supervision tree via use Hephaestus)
:persistent_term.put({HephaestusOban, :config, "my_app_hephaestus"}, %{
  repo: MyApp.Repo,
  oban: MyApp.Oban,
  storage: {HephaestusEcto.Storage, MyApp.Hephaestus.Storage}
})

# Every job args includes: %{"instance_id" => id, "config_key" => "my_app_hephaestus"}
# Workers resolve config via:
defp config(job), do: :persistent_term.get({HephaestusOban, :config, job.args["config_key"]})
```

This is the same pattern `Runner.Local` uses with `remember_registry/1` (persistent_term for registry lookup). After VM restart, the supervision tree calls `start_link` again which repopulates the persistent_term before any Oban job runs.

### 2.2 Database Schema — step_results

Auxiliary table for zero-contention parallel step execution.

```sql
CREATE TABLE hephaestus_step_results (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id     UUID         NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  step_ref        VARCHAR(255) NOT NULL,
  event           VARCHAR(255) NOT NULL,
  context_updates JSONB        NOT NULL DEFAULT '{}',
  processed       BOOLEAN      NOT NULL DEFAULT false,
  inserted_at     TIMESTAMP    NOT NULL DEFAULT now()
);

CREATE INDEX idx_step_results_pending ON hephaestus_step_results (instance_id) WHERE NOT processed;
```

**Why a separate table instead of optimistic locking on Instance:**
- Fan-out: N ExecuteStepWorkers write in parallel — each inserts its own row, zero contention
- No lost updates — AdvanceWorker is the single writer for the Instance
- No false retries polluting Oban dashboard
- No re-execution of side-effects (email sent twice, payment charged twice)

### 2.3 Workers

#### AdvanceWorker

Orchestrator. **Single writer for Instance.** Serialized per instance via Oban unique + advisory lock.

**Unique constraint:** Uses `period: :infinity` covering all non-terminal states to prevent duplicate AdvanceWorkers from being inserted while one is pending or executing. Requires Oban >= 2.14.

```elixir
defmodule HephaestusOban.AdvanceWorker do
  use Oban.Worker,
    queue: :hephaestus,
    unique: [keys: [:instance_id], period: :infinity,
             states: [:available, :scheduled, :executing, :retryable]]
```

**Advisory lock:** As a second layer of defense, the worker acquires a PostgreSQL advisory lock on the instance_id at the start of `perform/1`. This truly serializes execution even if two AdvanceWorkers slip past the unique check on different nodes.

```elixir
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => instance_id}} = job) do
    config = resolve_config(job)

    # Advisory lock serializes execution per instance
    lock_key = :erlang.phash2(instance_id)

    config.repo.transaction(fn ->
      # pg_advisory_xact_lock releases automatically when transaction ends
      config.repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

      instance = load_instance(config, instance_id)

      # 1. Apply pending step_results
      pending = StepResults.pending_for(config.repo, instance_id)
      instance = apply_step_results(instance, pending)

      # 2. Check for discarded step jobs -> workflow failure
      case detect_discarded_steps(config, instance) do
        [] -> :ok
        _failed -> fail_workflow(config, instance); throw(:failed)
      end

      # 3. Engine.advance (handles pending -> running, empty active -> completed)
      {:ok, instance} = Engine.advance(instance)

      # 4. Persist instance + mark results processed (atomic)
      persist(config, instance)
      StepResults.mark_processed(config.repo, pending)

      # 5. Decide next action
      case instance do
        %{status: s} when s in [:completed, :failed, :waiting] -> :ok
        %{active_steps: active} ->
          active
          |> MapSet.to_list()
          |> Enum.each(&enqueue_execute_step(config, instance_id, &1))
      end
    end)

    :ok
  end
end
```

**Key guarantees:**
- `pg_advisory_xact_lock` + `Repo.transaction` ensures step_results processing and Instance persist are atomic — no partial state on crash
- Advisory lock auto-releases when transaction ends (commit or crash)
- Unique constraint prevents queue buildup of duplicate AdvanceWorkers

**apply_step_results/2 iterates each pending result:**
```
for each step_result:
  step_module = String.to_existing_atom(step_result.step_ref)
  event = String.to_existing_atom(step_result.event)
  instance = Engine.complete_step(instance, step_module, event, step_result.context_updates)
  instance = Engine.activate_transitions(instance, step_module, event)
instance = Engine.check_completion(instance)
```

Note: events and step_refs are stored as strings in the DB and converted back to atoms via `String.to_existing_atom/1` before passing to Engine functions (which expect atoms).

#### ExecuteStepWorker

Executes a single step. Writes result to step_results table. Never touches Instance directly.

```elixir
defmodule HephaestusOban.ExecuteStepWorker do
  use Oban.Worker, queue: :hephaestus

  # max_attempts set dynamically from retry_config

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id, "step_ref" => step_ref}}) do
    instance = load_instance(id)  # read-only, for context
    step_module = String.to_existing_atom(step_ref)

    case Engine.execute_step(instance, step_module) do
      {:ok, event} ->
        StepResults.insert(id, step_ref, to_string(event), %{})
        enqueue_advance(id)
        :ok

      {:ok, event, context_updates} ->
        StepResults.insert(id, step_ref, to_string(event), context_updates)
        enqueue_advance(id)
        :ok

      {:async} ->
        # Mark instance as waiting, persist
        mark_waiting(id, step_module)
        :ok

      {:error, reason} ->
        {:error, reason}  # Oban handles retry
    end
  end
end
```

**Retry config resolution (most specific wins):**

```
1. Step.retry_config/0          <- per step (optional callback)
2. Workflow.default_retry_config/0  <- per workflow (optional callback)
3. HephaestusOban default       <- %{max_attempts: 5, backoff: :exponential}
4. Oban queue config            <- most generic
```

The AdvanceWorker resolves retry config when creating ExecuteStepWorker jobs:

```elixir
defp enqueue_execute_step(instance_id, step_module) do
  retry = resolve_retry_config(instance_id, step_module)

  HephaestusOban.ExecuteStepWorker.new(
    %{instance_id: instance_id, step_ref: to_string(step_module)},
    max_attempts: retry.max_attempts
  )
  |> Oban.insert()
end
```

#### ResumeWorker

Handles external events and durable timers. Follows the same pattern as ExecuteStepWorker: **writes only to step_results, never to the Instance directly.** AdvanceWorker remains the single Instance writer.

Note: `Engine.resume_step/3` internally calls `complete_step` + `activate_transitions`. To preserve the single-writer invariant, ResumeWorker does NOT call Engine.resume_step. Instead, it inserts a step_result with the resume event, and AdvanceWorker applies it via `Engine.complete_step` + `Engine.activate_transitions` — achieving the same result without direct Instance mutation.

The AdvanceWorker also needs to handle the status transition from `:waiting` to `:running` when it processes a resume step_result. This is done by checking if `instance.status == :waiting` and the resumed step is in `active_steps`, then setting status to `:running` before applying `complete_step`.

```elixir
defmodule HephaestusOban.ResumeWorker do
  use Oban.Worker, queue: :hephaestus, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"instance_id" => id, "step_ref" => step_ref, "event" => event}} = job) do
    config = resolve_config(job)

    # Only write to step_results — AdvanceWorker will apply
    StepResults.insert(config.repo, id, step_ref, event, %{})
    enqueue_advance(config, id)

    :ok
  end
end
```

### 2.4 Failure Detection via Telemetry

```elixir
defmodule HephaestusOban.FailureHandler do
  @doc """
  Attaches to Oban telemetry to detect discarded ExecuteStepWorker jobs.
  When a step job exhausts all retries, enqueues an AdvanceWorker
  so it can detect the failure and mark the workflow as :failed.
  """
  def attach do
    :telemetry.attach(
      "hephaestus-step-discarded",
      [:oban, :job, :stop],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, :stop], _measure, %{job: job, state: :discard}, _config) do
    if job.worker == "HephaestusOban.ExecuteStepWorker" do
      %{"instance_id" => instance_id} = job.args
      Oban.insert(HephaestusOban.AdvanceWorker.new(%{instance_id: instance_id}))
    end
  end

  def handle_event(_event, _measure, _meta, _config), do: :ok
end
```

**AdvanceWorker failure detection:**
```elixir
defp detect_discarded_steps(instance) do
  instance.active_steps
  |> MapSet.to_list()
  |> Enum.filter(fn step ->
    has_discarded_job?(instance.id, step)
  end)
end

defp fail_workflow(instance, failed_steps) do
  instance
  |> Map.put(:status, :failed)
  |> Map.put(:active_steps, MapSet.new())
  |> persist()

  cancel_pending_jobs(instance.id)
end
```

### 2.5 Runner Public API

```elixir
defmodule HephaestusOban.Runner do
  @behaviour Hephaestus.Runtime.Runner

  @impl Runner
  def start_instance(workflow, context, opts) do
    storage = Keyword.fetch!(opts, :storage)
    oban = Keyword.fetch!(opts, :oban)

    instance = Instance.new(workflow, context)
    :ok = storage_put(storage, instance)

    Oban.insert(oban, AdvanceWorker.new(%{instance_id: instance.id}))

    {:ok, instance.id}
  end

  @impl Runner
  def resume(instance_id, event) do
    Oban.insert(ResumeWorker.new(%{
      instance_id: instance_id,
      step_ref: get_current_step(instance_id),
      event: to_string(event)
    }))
    :ok
  end

  @impl Runner
  def schedule_resume(instance_id, step_ref, delay_ms) do
    {:ok, %Oban.Job{id: job_id}} = Oban.insert(oban_name(), ResumeWorker.new(
      %{instance_id: instance_id, step_ref: to_string(step_ref),
        event: "timeout", config_key: config_key()},
      scheduled_at: DateTime.add(DateTime.utc_now(), delay_ms, :millisecond)
    ))
    # Return job_id as reference — can be used with Oban.cancel_job/1 to cancel the timer
    {:ok, job_id}
  end
end
```

**Note on Runner behaviour return type:** The current `Runner` behaviour specifies `{:ok, reference()}` for `schedule_resume`. This will be updated to `{:ok, term()}` in hephaestus_core to accommodate both `Process.send_after` references (Runner.Local) and Oban job IDs (Runner.Oban).
```

### 2.6 Complete Flow Diagram

```
start_instance(OrderWorkflow, %{order_id: 123})
  │
  ├─ Instance.new() → persist via HephaestusEcto.Storage
  └─ Oban.insert(AdvanceWorker)
       │
       ▼
  AdvanceWorker
  │ Engine.advance() → active_steps: {Validate, Charge, Notify}
  │ persist Instance
  └─ enqueue 3x ExecuteStepWorker
       │
       ├─ ExecuteStepWorker(Validate) ──┐
       ├─ ExecuteStepWorker(Charge)  ───┤  parallel, zero contention
       └─ ExecuteStepWorker(Notify)  ───┤
                                        │
       each: execute step               │
             INSERT step_results        │
             enqueue AdvanceWorker      │
                                        ▼
  AdvanceWorker (unique, serialized)
  │ SELECT step_results WHERE NOT processed
  │ apply each: Engine.complete_step + activate_transitions
  │ Engine.check_completion()
  │ persist Instance
  │
  ├─ :completed → done
  ├─ :waiting   → done (awaits ResumeWorker)
  └─ active_steps not empty → enqueue ExecuteStepWorkers (next wave)

  --- async step flow ---

  ExecuteStepWorker(WaitForEvent)
  │ Engine.execute_step → {:async}
  │ mark_waiting(instance, step)
  └─ done (no AdvanceWorker enqueued)

       ... external event ...

  Runner.resume(id, :payment_confirmed)
  └─ Oban.insert(ResumeWorker)
       │
       ▼
  ResumeWorker
  │ INSERT step_results(step, event)  ← only writes to step_results
  └─ enqueue AdvanceWorker
       │
       ▼
  AdvanceWorker
  │ detects instance is :waiting + resume step_result pending
  │ sets status :running, applies complete_step + activate_transitions
  │ persist
  └─ enqueue ExecuteStepWorkers → cycle continues

  --- failure flow ---

  ExecuteStepWorker(Charge)
  │ attempt 1 → {:error, :timeout}     (Oban retries)
  │ attempt 2 → {:error, :timeout}
  │ attempt N → {:error, :timeout}     → DISCARDED
  │
  ▼
  FailureHandler (telemetry)
  │ detects discard
  └─ enqueue AdvanceWorker
       │
       ▼
  AdvanceWorker
  │ detect_discarded_steps → [:Charge]
  │ instance.status = :failed
  │ cancel pending jobs
  └─ done

  --- durable timer flow ---

  ExecuteStepWorker(Wait)
  │ {:async} → mark waiting
  │ Runner.schedule_resume(id, :wait, 30_000)
  └─ Oban.insert(ResumeWorker, scheduled_at: now + 30s)

       ... 30 seconds later (survives crash, VM restart) ...

  ResumeWorker
  │ INSERT step_results(:wait, "timeout")
  └─ enqueue AdvanceWorker → applies resume, cycle continues
```

### 2.7 Migration Generator

```bash
mix hephaestus_oban.gen.migration
```

Generates migration for `hephaestus_step_results` table. Requires `hephaestus_ecto` migration to be run first (FK reference).

### 2.8 Consumer Usage

```elixir
# mix.exs
{:hephaestus_ecto, "~> 0.1"},
{:hephaestus_oban, "~> 0.1"}

# Generate and run migrations
$ mix hephaestus_ecto.gen.migration
$ mix hephaestus_oban.gen.migration
$ mix ecto.migrate

# lib/my_app/hephaestus.ex
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
    runner: {HephaestusOban.Runner, oban: MyApp.Oban}
end

# application.ex
children = [
  MyApp.Repo,
  {Oban, name: MyApp.Oban, repo: MyApp.Repo, queues: [hephaestus: 10]},
  MyApp.Hephaestus
]
```

### 2.9 Module Structure

```
lib/
  hephaestus_oban/
    runner.ex                # @behaviour Runner implementation
    workers/
      advance_worker.ex      # Orchestrator, single Instance writer
      execute_step_worker.ex # Step executor, writes to step_results
      resume_worker.ex       # External events and durable timers
    step_results.ex          # CRUD for step_results table
    failure_handler.ex       # Telemetry listener for discarded jobs
    retry_config.ex          # Retry config resolution logic
    schema/
      step_result.ex         # Ecto schema for step_results
    migration.ex             # Migration module used by generator
mix/
  tasks/
    hephaestus_oban.gen.migration.ex  # Mix task
```

---

## Part 3: Changes to hephaestus_core

### 3.1 Macro `use Hephaestus` — accept tuple {module, opts}

**File:** `lib/hephaestus.ex`

Current: `storage: ModuleName` (atom only)
New: also accepts `storage: {ModuleName, opts}` and `runner: {ModuleName, opts}`

The `child_spec/1` generated by the macro must unpack the tuple and pass opts to `start_link`:

```elixir
# Current
{@hephaestus_storage, name: storage_name}

# New — when storage is {module, opts}
{storage_module, Keyword.merge(storage_opts, [name: storage_name])}
```

**Backward compatible:** `storage: Hephaestus.Runtime.Storage.ETS` continues to work unchanged.

### 3.2 Step behaviour — optional retry_config/0

**File:** `lib/hephaestus/steps/step.ex`

Add optional callback:

```elixir
@type retry_config :: %{
  max_attempts: pos_integer(),
  backoff: :exponential | :linear | :constant,
  max_backoff: pos_integer()  # milliseconds
}

@callback retry_config() :: retry_config()
@optional_callbacks retry_config: 0
```

Runner.Local ignores this callback. HephaestusOban.Runner reads it to configure Oban job max_attempts.

### 3.3 Workflow — optional default_retry_config/0

No file change needed. The workflow module is a regular Elixir module — it can define `default_retry_config/0` without a behaviour callback. HephaestusOban checks with `function_exported?/3`:

```elixir
if function_exported?(workflow, :default_retry_config, 0) do
  workflow.default_retry_config()
else
  @default_retry_config
end
```

This avoids adding an optional callback to the Workflow macro for a feature only used by hephaestus_oban.

### 3.4 Runner behaviour — schedule_resume return type

**File:** `lib/hephaestus/runtime/runner.ex`

Change `schedule_resume` return type from `{:ok, reference()}` to `{:ok, term()}`. Runner.Local returns a timer reference, Runner.Oban returns an Oban job ID — both are valid opaque handles.

### 3.5 runner_opts propagation

**File:** `lib/hephaestus.ex`

The `runner_opts/0` private function must also propagate runner-specific opts (like `oban: MyApp.Oban`) so the Runner can access them.

When runner is `{HephaestusOban.Runner, oban: MyApp.Oban}`:

```elixir
defp runner_opts do
  [
    storage: {@hephaestus_storage, Module.concat(__MODULE__, Storage)},
    registry: Module.concat(__MODULE__, Registry),
    dynamic_supervisor: Module.concat(__MODULE__, DynamicSupervisor),
    task_supervisor: Module.concat(__MODULE__, TaskSupervisor)
  ] ++ @hephaestus_runner_opts  # merged runner-specific opts
end
```

---

## Concurrency Model (step_results table)

### Problem

In fan-out, N ExecuteStepWorkers run in parallel. If they all update the Instance directly:
- Lost updates (last writer wins, earlier changes lost)
- Re-execution of side-effects on retry (email sent twice)
- False errors in Oban dashboard from optimistic lock retries

### Solution

ExecuteStepWorkers and ResumeWorkers never write to the Instance. They INSERT into `step_results` (zero contention — each writes its own row). AdvanceWorker is the **single writer** for the Instance, serialized via Oban unique constraint + PostgreSQL advisory lock. All Instance mutations happen inside a `Repo.transaction` with `pg_advisory_xact_lock` — ensuring atomicity between step_results processing and Instance persistence.

### Fan-in Behavior

Fan-in is handled by the Engine's existing `__predecessors__` check:

```
AdvanceWorker applies step_result(C):
  Engine.activate_transitions(C) → target is JoinStep
  Engine.maybe_activate_step(JoinStep):
    predecessors = workflow.__predecessors__(JoinStep)  # {A, B, C}
    MapSet.subset?({A, B, C}, completed_steps)
    → if {A, B, C} ⊆ {B, C} → false, don't activate
    → if {A, B, C} ⊆ {A, B, C} → true, activate JoinStep
```

No special handling needed — the Engine's pure functional logic handles fan-in correctly.

---

## Error Handling

| Scenario | Handler | Outcome |
|----------|---------|---------|
| Step returns `{:error, reason}` | Oban retry with backoff | Retried up to max_attempts |
| Step exhausts all retries | FailureHandler (telemetry) | Workflow marked `:failed` |
| Step crashes/raises | Oban catches, treats as error | Same retry flow |
| AdvanceWorker fails | Oban retry | Idempotent — re-applies unprocessed step_results |
| ResumeWorker fails | Oban retry | Idempotent — INSERT step_result is deduplicated by (instance_id, step_ref) or is a no-op if already processed |
| DB connection lost | Oban retry | All workers are idempotent |
| Instance stuck (no jobs) | ReconcileWorker (cron, future) | Safety net, not in MVP |

---

## Testing Strategy

### hephaestus_ecto

- Unit tests: Serializer round-trip (Instance -> DB -> Instance)
- Integration tests: Storage behaviour compliance (get/put/delete/query against real Postgres)
- Concurrency tests: parallel puts, get during writes
- Migration test: migration runs cleanly up and down

### hephaestus_oban

- Unit tests: each worker in isolation with mocked storage
- Integration tests: full workflow execution (linear, fan-out/fan-in, async/resume)
- Failure tests: step failure -> retry -> discard -> workflow :failed
- Timer tests: schedule_resume creates Oban job with correct scheduled_at
- Concurrency tests: fan-out with 3+ parallel steps, verify no lost updates

### hephaestus_core changes

- Existing 125 tests must continue passing (no regressions)
- New tests: tuple config in `use Hephaestus`
- New tests: `retry_config/0` optional callback

---

## Migration Path for Existing Users

```
# Before (ETS + Local)
use Hephaestus,
  storage: Hephaestus.Runtime.Storage.ETS,
  runner: Hephaestus.Runtime.Runner.Local

# After (Ecto + Oban)
use Hephaestus,
  storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
  runner: {HephaestusOban.Runner, oban: MyApp.Oban}

# Mixed (Ecto storage + Local runner) — also valid
use Hephaestus,
  storage: {HephaestusEcto.Storage, repo: MyApp.Repo},
  runner: Hephaestus.Runtime.Runner.Local
```

All combinations work. Storage and Runner are independent adapters.
