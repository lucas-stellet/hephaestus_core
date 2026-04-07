# Architecture

Hephaestus is a workflow engine for Elixir built around a pure functional core
and pluggable runtime adapters. Workflows are directed acyclic graphs (DAGs) of
steps, validated at compile time, executed at runtime through adapter contracts.
This guide explains the internal architecture and the reasoning behind it.

## Design philosophy

Three principles shape the design:

1. **Pure core, effectful shell.** The engine that advances workflow state is a
   pure function — no GenServers, no storage calls, no side effects. Side effects
   live in runtime adapters that wrap the core.

2. **Fail at compile time.** The workflow macro extracts the step graph from
   `start/0` and `transit/3` at compilation, then validates it with `libgraph`.
   Cycles, unreachable steps, missing terminal nodes, event mismatches, and
   context key collisions are all compile errors — not runtime surprises.

3. **Adapter contracts, not implementations.** Storage and execution are
   behaviours. The core library ships ETS and local OTP defaults so you can
   develop and test without external dependencies. Production adapters (Ecto,
   Oban) live in separate packages and plug into the same contracts.

## Layer diagram

```
+---------------------------------------------------------------+
|                       Consumer Application                    |
|   use Hephaestus, storage: ..., runner: ...                   |
+---------------------------------------------------------------+
          |                                         |
          v                                         v
+-------------------+                     +-------------------+
|    Runner          |                     |    Storage         |
|    (behaviour)     |                     |    (behaviour)     |
+-------------------+                     +-------------------+
| Runner.Local       |                     | Storage.ETS       |
| (GenServer/OTP)    |                     | (GenServer/ETS)   |
+-------------------+                     +-------------------+
          |                                         |
          +------------------+----------------------+
                             |
                             v
               +---------------------------+
               |     Hephaestus.Core       |
               |  Engine  |  Instance      |
               |  Context |  Workflow      |
               |  ExecutionEntry           |
               +---------------------------+
                             |
                             v
               +---------------------------+
               |     Step / Connector      |
               |     (behaviours)          |
               +---------------------------+
```

The **Core** layer is pure Elixir structs and functions — no processes, no I/O.
The **Runtime** layer provides the OTP wiring and persistence. Consumer
applications compose them through `use Hephaestus`.

## Core modules

### Instance (`Hephaestus.Core.Instance`)

The central data structure. An Instance is a snapshot of a workflow execution at
a point in time:

| Field               | Type                  | Purpose                                     |
|---------------------|-----------------------|---------------------------------------------|
| `id`                | UUID v4 string        | Unique identifier                            |
| `workflow`          | module                | The workflow module being executed            |
| `status`            | atom                  | Lifecycle state (see below)                  |
| `current_step`      | module or nil         | The step currently being processed            |
| `context`           | `Context.t()`         | Initial data + accumulated step results       |
| `step_configs`      | map                   | Per-step config overrides                     |
| `active_steps`      | MapSet                | Steps currently executing (supports parallel) |
| `completed_steps`   | MapSet                | Steps that have finished                      |
| `execution_history` | list of ExecutionEntry| Audit trail                                  |

Instances are created via `Instance.new/2` and are plain structs — the Instance
module has no process or side effect.

### Context (`Hephaestus.Core.Context`)

The execution context has two namespaced maps:

- **`initial`** — immutable data provided at workflow start (e.g., `%{order_id: 123}`).
- **`steps`** — results accumulated from completed steps, keyed by step ref.

Namespacing matters for fan-in: when parallel branches converge, each step
writes to its own key, avoiding conflicts.

```elixir
context.initial.order_id       #=> 123
context.steps.validate.valid   #=> true
context.steps.charge.amount    #=> 4999
```

### Engine (`Hephaestus.Core.Engine`)

The pure functional heart. Every function takes an Instance struct and returns an
updated Instance struct. No GenServer, no storage, no side effects.

Key operations:

- **`advance/1`** — moves the instance forward. If `:pending`, activates the
  start step. If active steps remain, returns as-is. If no active steps and not
  waiting, marks `:completed`.

- **`execute_step/2`** — calls `step_module.execute/3` with the instance,
  config, and context. Returns the step's result tuple.

- **`complete_step/4`** — moves a step from `active_steps` to `completed_steps`,
  merges context updates, cleans up config.

- **`activate_transitions/3`** — resolves the workflow's `transit/3` for the
  completed step and event, then activates target steps. Supports single targets,
  `{target, config}` tuples, and lists (fan-out). Applies **join semantics**:
  a step is only activated if all its predecessors have completed.

- **`resume_step/3`** — completes a waiting async step, activates its
  transitions, and sets status back to `:running`.

Because the engine is pure, it is trivial to test: build an Instance, call
engine functions, assert on the returned struct. No mocks needed.

### Workflow (`Hephaestus.Core.Workflow` + `Hephaestus.Workflow`)

The behaviour module defines the contract (`start/0`, `transit/3`). The macro
module (`Hephaestus.Workflow`) handles compile-time extraction and validation.

When you write:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow

  def start, do: ValidateOrder

  def transit(ValidateOrder, :valid, _ctx), do: ChargePayment
  def transit(ValidateOrder, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(ChargePayment, :charged, _ctx), do: Hephaestus.Steps.Done
end
```

At compile time, the macro:

1. Extracts `start/0` to find the entry point.
2. Walks all `transit/3` clauses to build an edge list (static clauses are
   extracted from the AST; dynamic clauses use `@targets` annotations).
3. Calls `Hephaestus.Core.Workflow.validate!/4` which builds a `libgraph`
   digraph and runs six validations.
4. Generates `__predecessors__/1`, `__graph__/0`, and `__edges__/0` into the
   workflow module for runtime use.

### ExecutionEntry (`Hephaestus.Core.ExecutionEntry`)

An immutable record appended to the instance's `execution_history` as steps
complete. Contains `step_ref`, `event`, `timestamp`, and optional
`context_updates`. Useful for audit trails and debugging.

## Workflow lifecycle

```
                       Instance.new/2
                            |
                            v
                       +---------+
                       | pending |
                       +----+----+
                            |  Engine.advance/1
                            v
                       +---------+
              +------->| running |<------+
              |        +----+----+       |
              |             |            |
         resume_step   execute steps   activate
         (async done)       |         transitions
              |             v            |
              |     +-------+-------+    |
              |     |               |    |
              |     v               v    |
         +---------+         +----------+---+
         | waiting |         | step returns |
         +---------+         | {:ok, event} |
                             +--------------+
                                    |
                         no active steps remain
                                    |
                                    v
                             +-----------+
                             | completed |
                             +-----------+

         (any step returns {:error, _})
                       |
                       v
                  +--------+
                  | failed |
                  +--------+
```

**Status transitions:**

| From      | To        | Trigger                                    |
|-----------|-----------|--------------------------------------------|
| pending   | running   | `Engine.advance/1` activates the start step |
| running   | running   | Step completes, transitions activate more   |
| running   | waiting   | Step returns `{:async}`                     |
| running   | completed | No active steps remain                      |
| running   | failed    | Step returns `{:error, reason}`             |
| waiting   | running   | `Engine.resume_step/3` with external event  |

## Compile-time DAG validation

`Hephaestus.Core.Workflow.validate!/4` runs six checks at compile time:

1. **Acyclic** — the graph must be a DAG. Cycles are always a compile error.
2. **Reachable** — every step must be reachable from `start/0`. Orphaned steps
   are a compile error.
3. **Leaf termination** — every leaf node (step with no outgoing edges) must be
   `Hephaestus.Steps.Done`. Paths that dead-end elsewhere are rejected.
4. **Fan-out convergence** — when a step fans out to multiple parallel branches,
   those branches must converge at a common join point before `Done`.
5. **Context key uniqueness** — no two steps may resolve to the same context key
   (derived from the module name or `step_key/0`). Collisions would silently
   overwrite data.
6. **Event consistency** — every event declared in a step's `events/0` must have
   a matching `transit/3` clause, and every event used in `transit/3` must be
   declared in the step's `events/0`. No orphaned events, no undeclared
   transitions.

These checks catch entire classes of bugs at build time rather than in
production.

## Runner adapter pattern

The `Hephaestus.Runtime.Runner` behaviour defines three callbacks:

- `start_instance/3` — create and begin executing a workflow.
- `resume/2` — deliver an event to a waiting instance.
- `schedule_resume/3` — schedule a delayed `:timeout` resume for a step.

### Local runner (`Hephaestus.Runtime.Runner.Local`)

The built-in implementation. One GenServer per workflow instance, started as a
transient child under a `DynamicSupervisor`. The execution loop:

1. `init/1` — recovers the latest persisted state from storage (crash recovery).
   If the instance is already completed or failed, the process stops immediately.
2. `{:continue, :advance}` — calls `Engine.advance/1`. Based on the result:
   - **completed** → persist and stop.
   - **waiting** → persist and park (no further continues).
   - **running with active steps** → persist and continue to `:execute_active`.
3. `{:continue, :execute_active}` — fans out all active steps via
   `Task.Supervisor.async_nolink/2`, awaits results, then reduces them through
   `Engine.complete_step/4` and `Engine.activate_transitions/3`. Steps execute
   concurrently within a single advance cycle.
4. **Resume** — `GenServer.cast({:resume, event})` calls `Engine.resume_step/3`
   and re-enters the advance loop.

The Local runner is suitable for development, testing, and single-node
deployments. Timers from `schedule_resume/3` are process-local and do not survive
crashes.

## Storage adapter pattern

The `Hephaestus.Runtime.Storage` behaviour defines four callbacks:

- `get/1` — retrieve an instance by ID.
- `put/1` — persist (upsert) an instance.
- `delete/1` — remove an instance.
- `query/1` — filter instances by status, workflow, etc.

### ETS storage (`Hephaestus.Runtime.Storage.ETS`)

The built-in implementation. A GenServer that owns a named ETS table (`:set`,
`:protected`). All operations go through `GenServer.call/2` to serialize writes
and ensure consistency. Queries do a full table scan with in-memory filtering —
fine for development, not for production scale.

## Step behaviour

Every step implements `Hephaestus.Steps.Step`:

```elixir
@callback events() :: [atom()]
@callback execute(Instance.t(), config(), Context.t()) :: result()

# Optional
@callback step_key() :: atom()
@callback retry_config() :: retry_config()
```

### Return values from `execute/3`

| Return                        | Meaning                                          |
|-------------------------------|--------------------------------------------------|
| `{:ok, event}`                | Synchronous completion, emit event               |
| `{:ok, event, context_updates}` | Synchronous completion with data                |
| `{:async}`                    | Step will complete later (instance enters waiting)|
| `{:error, reason}`            | Step failed                                      |

### Async pattern

When a step returns `{:async}`, the instance enters `:waiting` status and the
runner parks. Some external trigger (webhook, user action, timer) later calls
`resume/2` with an event atom, which flows through `Engine.resume_step/3` to
unblock the workflow.

The `schedule_resume/3` callback supports timer-based async: the runner
automatically delivers a `:timeout` event after a delay.

### Step key resolution

Each step's context results are stored under a key derived from:

1. `step_key/0` if the step implements it (explicit override).
2. Otherwise, the last segment of the module name, underscored
   (e.g., `MyApp.Steps.ValidateOrder` → `:validate_order`).

The compile-time validator ensures no two steps in a workflow share the same key.

## Fan-out and fan-in

Hephaestus supports parallel execution through its transition system:

**Fan-out** — a `transit/3` clause returns a list of targets:

```elixir
def transit(PrepareOrder, :ready, _ctx), do: [ChargePayment, ReserveInventory]
```

Both `ChargePayment` and `ReserveInventory` become active simultaneously. The
Local runner executes them concurrently via `Task.Supervisor`.

**Fan-in (join semantics)** — `Engine.activate_transitions/3` checks
`__predecessors__/1` before activating a step. A step is only activated when
**all** of its predecessors have completed:

```
  PrepareOrder
      |
  :ready (fan-out)
     / \
    v   v
 Charge  Reserve
    \   /
  :charged + :reserved (fan-in)
     \ /
      v
  ShipOrder      <-- only activates when BOTH predecessors complete
```

The predecessor map is computed at compile time from the DAG, so join logic has
zero runtime overhead for graph traversal.

## Connector pattern

The `Hephaestus.Connectors.Connector` behaviour provides a contract for
external service integrations:

```elixir
@callback execute(action(), params(), config()) :: {:ok, result()} | {:error, reason()}
@callback supported_actions() :: [action()]
```

Connectors are not called by the engine directly — steps use them internally.
This separation keeps the engine pure and makes external dependencies explicit
and testable. A step can inject a connector module via its config, making it
straightforward to swap a real connector for a test double.

## Supervision tree

When you `use Hephaestus` and add the module to your application supervisor,
it starts:

```
MyApp.Hephaestus (Supervisor, :one_for_one)
  |-- MyApp.Hephaestus.Registry (Registry, :unique)
  |-- MyApp.Hephaestus.DynamicSupervisor (DynamicSupervisor)
  |-- MyApp.Hephaestus.TaskSupervisor (Task.Supervisor)
  |-- MyApp.Hephaestus.Storage (Storage adapter, e.g., ETS)
```

Each workflow instance is a transient child under the `DynamicSupervisor`,
registered by instance ID in the `Registry`. The `TaskSupervisor` runs
concurrent step executions.

## Future: Ecto and Oban adapters

The adapter pattern exists specifically to support production-grade alternatives:

- **`hephaestus_ecto`** — a `Storage` adapter that persists instances as JSONB
  in PostgreSQL via Ecto. Enables durable workflows that survive node restarts.
- **`hephaestus_oban`** — a `Runner` adapter that uses Oban workers instead of
  GenServer processes. Brings distributed execution, persistent job queues,
  and advisory-lock-based concurrency control.

These packages will implement the same `Storage` and `Runner` behaviours. No
changes to your workflow definitions or step implementations — swap the adapter
in `use Hephaestus` and the runtime changes underneath.
