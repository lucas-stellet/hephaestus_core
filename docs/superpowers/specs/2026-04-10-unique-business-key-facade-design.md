# Unique Business Key & Workflow Facade

**Date:** 2026-04-10
**Status:** Approved
**Scope:** hephaestus_core 0.2.0, hephaestus_ecto 0.2.0, hephaestus_oban 0.4.0

## Problem

Hephaestus workflow instances are identified by auto-generated UUIDs. Consumers that need to resume workflows from external events (e.g., webhooks, user actions) must either carry the UUID through the entire event chain or perform lookup queries to find the right instance. This creates coupling between event producers and the workflow runtime.

Industry-standard workflow engines (Temporal, AWS Step Functions, Camunda, Oban Pro Workflows) solve this by letting the caller provide a business-meaningful ID at start time, eliminating the need for lookup.

## Solution

Every workflow declares a mandatory business key. The key becomes the identity prefix for all instances of that workflow. A facade on the workflow module provides `start/2`, `resume/2`, `get/1`, `list/1`, and `cancel/1` — the caller only ever passes the raw business value. A dedicated `Hephaestus.Uniqueness` module handles ID construction, validation, and uniqueness checks.

## Design

### 1. Workflow DSL — `unique` option

The `use Hephaestus.Workflow` macro accepts a mandatory `:unique` keyword list, converted internally to a `%Hephaestus.Workflow.Unique{}` struct.

#### Struct

```elixir
defmodule Hephaestus.Workflow.Unique do
  @enforce_keys [:key]
  defstruct [:key, scope: :workflow]

  @type scope :: :workflow | :version | :global | :none
  @type t :: %__MODULE__{
    key: String.t(),
    scope: scope()
  }

  @valid_scopes [:workflow, :version, :global, :none]
  @key_format ~r/^[a-z0-9]+$/

  @doc """
  Creates a validated `%Unique{}` struct from a keyword list.

  Raises `ArgumentError` with a descriptive message if any field is invalid.
  Called at compile-time by the Workflow macro.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    unique = struct!(__MODULE__, opts)
    validate_key!(unique.key)
    validate_scope!(unique.scope)
    unique
  end

  defp validate_key!(key) when is_binary(key) do
    unless Regex.match?(@key_format, key) do
      raise ArgumentError,
        "unique key must contain only lowercase letters and numbers [a-z0-9], got: #{inspect(key)}"
    end
  end

  defp validate_key!(key) do
    raise ArgumentError,
      "unique key must be a string, got: #{inspect(key)}"
  end

  defp validate_scope!(scope) when scope in @valid_scopes, do: :ok

  defp validate_scope!(scope) do
    raise ArgumentError,
      "unique scope must be one of #{inspect(@valid_scopes)}, got: #{inspect(scope)}"
  end
end
```

#### Validation errors

The `new!/1` constructor is called at compile-time by the Workflow macro. Invalid configurations produce clear errors during compilation:

| Invalid input | Error message |
|---|---|
| `key: 123` | "unique key must be a string, got: 123" |
| `key: "Blueprint"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"Blueprint\"" |
| `key: "blueprint-id"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"blueprint-id\"" |
| `key: "blueprint_id"` | "unique key must contain only lowercase letters and numbers [a-z0-9], got: \"blueprint_id\"" |
| `scope: :invalid` | "unique scope must be one of [:workflow, :version, :global, :none], got: :invalid" |
| missing `key` | "the following keys must also be given when building struct Hephaestus.Workflow.Unique: [:key]" |

#### Fields

##### `key` (required)

The business key that identifies the instance. Defines the prefix of the stored ID.

**Format:** String, only `[a-z0-9]`. No hyphens, underscores, or uppercase.

**Example:**

```elixir
unique: [key: "blueprintid"]

# start("abc123", ctx) -> stored ID: "blueprintid::abc123"
# start("550e8400-e29b-41d4-a716-446655440000", ctx) -> "blueprintid::550e8400-e29b-41d4-a716-446655440000"
```

**Use case:** "For each blueprint, only one incorporation workflow can exist." The key declares which business entity the workflow tracks. The caller never constructs the ID — only passes the value.

##### `scope` (default: `:workflow`)

Defines the perimeter where uniqueness is enforced. When the caller tries to start an instance that already exists (status `:pending`, `:running`, or `:waiting`) within the perimeter, it receives `{:error, :already_running}`.

###### `:workflow` — uniqueness per `{id, workflow_module}`

The ID is unique within the same workflow module, regardless of version. Different workflows can have active instances with the same ID simultaneously.

**Uniqueness key:** `{id, workflow_module}`

**Example:**

```elixir
defmodule IncorporationFlow do
  use Hephaestus.Workflow,
    versions: %{1 => V1, 2 => V2}, current: 2,
    unique: [key: "blueprintid", scope: :workflow]
end

defmodule OnboardingFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "blueprintid", scope: :workflow]
end
```

```elixir
# Same blueprint, different workflows
IncorporationFlow.start("abc123", ctx)   # -> {:ok, "blueprintid::abc123"}
OnboardingFlow.start("abc123", ctx)      # -> {:ok, "blueprintid::abc123"} (different workflow)

# Same blueprint, same workflow
IncorporationFlow.start("abc123", ctx)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx)   # -> {:error, :already_running}

# Same blueprint, different versions of same workflow
IncorporationFlow.start("abc123", ctx)                 # V1 running -> :waiting
IncorporationFlow.start("abc123", ctx, version: 2)     # -> {:error, :already_running}
# Version doesn't matter — scope is the entire workflow module
```

**Use case:** Different workflows operate on the same resource independently. Blueprint "abc123" can be in an incorporation process AND an onboarding process at the same time — they are independent flows. But within the same workflow, only one active instance per blueprint.

**When to use:** Most common case. Each workflow is responsible for one business flow over a resource. Different flows coexist, duplicates within the same flow do not.

###### `:version` — uniqueness per `{id, workflow_module, version}`

The ID is unique within the same version of a workflow. Different versions of the same workflow can have active instances with the same ID simultaneously.

**Uniqueness key:** `{id, workflow_module, version}`

**Example:**

```elixir
defmodule IncorporationFlow do
  use Hephaestus.Workflow,
    versions: %{1 => V1, 2 => V2}, current: 2,
    unique: [key: "blueprintid", scope: :version]
end
```

```elixir
# Same blueprint, different versions
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx, version: 2)   # -> {:ok, "blueprintid::abc123"} (different version)

# Same blueprint, same version
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:ok, "blueprintid::abc123"}
IncorporationFlow.start("abc123", ctx, version: 1)   # -> {:error, :already_running}
```

**Use case:** Gradual migration between versions. Rolling out V2 of the incorporation workflow. Blueprint "abc123" has a V1 instance in `:waiting` (awaiting seller action). Start V2 for the same blueprint without canceling V1 — both versions coexist during the transition period. When V1 completes or is cancelled, only V2 remains.

**When to use:** Blue-green deploys, canary releases, or any scenario where two versions of the same workflow must run in parallel over the same resource. Rare but necessary in systems that cannot interrupt in-progress workflows during deploys.

###### `:global` — uniqueness per `{id}`

The ID is unique across the entire system. No workflow, of any type or version, can have an active instance with the same ID.

**Uniqueness key:** `{id}`

**Example:**

```elixir
defmodule OnboardingFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "companyid", scope: :global]
end

defmodule ComplianceFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "companyid", scope: :global]
end
```

```elixir
# Same company ID, different workflows
OnboardingFlow.start("abc123", ctx)    # -> {:ok, "companyid::abc123"}
ComplianceFlow.start("abc123", ctx)    # -> {:error, :already_running}
# Even though they are different workflows, the ID is global

# After onboarding completes
# OnboardingFlow "abc123" -> :completed (releases the ID)
ComplianceFlow.start("abc123", ctx)    # -> {:ok, "companyid::abc123"}
```

**Use case:** The ID represents a resource that can only have one active flow of any type. Example: company onboarding — while onboarding is in progress, no other workflow (compliance, billing, etc.) can start for that company. Guarantees flow sequencing over the same resource.

**When to use:** Exclusive processes where the resource must be "free" before entering another flow. Compliance, onboarding, data migration — situations where concurrent flows over the same resource would cause inconsistency.

###### `:none` — business key without uniqueness constraint

The ID uses the business key prefix, but there is no uniqueness verification. Multiple active instances with the same ID are allowed.

**Uniqueness key:** none

**Example:**

```elixir
defmodule NotificationFlow do
  use Hephaestus.Workflow,
    version: 1,
    unique: [key: "userid", scope: :none]
end
```

```elixir
# Multiple notifications for the same user
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::r7x9k2"}
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::m3p8w1"} (another instance)
NotificationFlow.start("abc123", ctx)   # -> {:ok, "userid::abc123::q2n5j4"} (yet another)
# Each instance gets a unique random suffix to avoid ID collision in storage
```

**Use case:** The workflow needs a business key for identity and to use facade functions (`list/1`), but the flow's nature allows multiple simultaneous executions. Example: notification workflow — the same user can have several notifications in progress. The `"userid::"` prefix allows listing all instances for a user, but doesn't prevent new ones.

**When to use:** Workflows that are inherently non-exclusive. The resource doesn't need to be "reserved" — the workflow tracks events, doesn't control access.

**Note:** With `scope: :none`, `resume/2` and `get/1` are **not generated** — they would be ambiguous with multiple instances sharing the same ID. The caller uses `list/1` to find instances and operates via `MyApp.Hephaestus.resume/2` with the full ID.

#### Compile-time validations

- `unique` is mandatory — every workflow must declare a business key
- `key` must be present and match `~r/^[a-z0-9]+$/`
- `scope` must be `:workflow`, `:version`, `:global`, or `:none`

#### Generated function

- `__unique__/0` — returns the `%Hephaestus.Workflow.Unique{}` struct

### 2. Hephaestus.Uniqueness — dedicated module

Encapsulates ID construction, validation, and uniqueness checking. Keeps the Workflow macro and Runner lean.

#### Responsibilities

- `build_id/2` — constructs the composite ID from Unique config and value
- `build_id_with_suffix/2` — constructs composite ID with random suffix (for `scope: :none`)
- `validate_value!/1` — validates the caller-provided value
- `check/5` — verifies uniqueness by querying Storage (returns `:ok` or `{:error, :already_running}`)
- `extract_value/1` — extracts the raw value from a composite ID

#### ID format

Format: `"key::value"`

- Separator: `::` (reserved, caller cannot use)
- Key: `[a-z0-9]+`
- Value: `[a-z0-9]+` or UUID (`[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`)
- Future sub-contexts: `"key::value::subkey::subvalue"`

The `-` character is **only** permitted inside valid UUIDs (8-4-4-4-12 hex format). Outside of UUIDs, only `[a-z0-9]` is allowed.

#### Implementation

```elixir
defmodule Hephaestus.Uniqueness do
  alias Hephaestus.Workflow.Unique

  @active_statuses [:pending, :running, :waiting]

  def build_id(%Unique{key: key}, value) do
    validate_value!(value)
    "#{key}::#{value}"
  end

  def build_id_with_suffix(%Unique{key: key}, value) do
    validate_value!(value)
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{key}::#{value}::#{suffix}"
  end

  def extract_value(id) do
    case String.split(id, "::") do
      [_key, value] -> value
      [_key, value, _suffix] -> value  # scope: :none IDs have a random suffix
      _ -> raise ArgumentError, "invalid unique id format: #{id}"
    end
  end

  def validate_value!(value) when is_binary(value) do
    unless valid_value?(value) do
      raise ArgumentError,
        "invalid id value: #{inspect(value)}. Must be [a-z0-9]+ or a valid UUID"
    end
  end

  defp valid_value?(value) do
    simple_value?(value) or uuid_value?(value)
  end

  defp simple_value?(value), do: Regex.match?(~r/^[a-z0-9]+$/, value)

  defp uuid_value?(value),
    do: Regex.match?(~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/, value)

  # scope: :none — no uniqueness check, always ok
  def check(%Unique{scope: :none}, _id, _workflow, _version, _query_fn), do: :ok

  # scope: :workflow — unique per {id, workflow_module}
  def check(%Unique{scope: :workflow}, id, workflow, _version, query_fn) do
    case query_fn.(id: id, workflow: workflow, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end

  # scope: :version — unique per {id, workflow_module, version}
  def check(%Unique{scope: :version}, id, workflow, version, query_fn) do
    case query_fn.(id: id, workflow: workflow, workflow_version: version, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end

  # scope: :global — unique per {id}
  def check(%Unique{scope: :global}, id, _workflow, _version, query_fn) do
    case query_fn.(id: id, status_in: @active_statuses) do
      [] -> :ok
      [_ | _] -> {:error, :already_running}
    end
  end
end
```

### 3. Workflow Facade — generated functions

When a workflow defines `unique`, the macro generates facade functions in the umbrella module (or standalone module). These are thin wrappers that construct the ID via Uniqueness and delegate to the Hephaestus module discovered via Instances registry.

#### Generated functions

| Function | Signature | Description |
|---|---|---|
| `start/2` | `start(value, context)` | Build ID, check uniqueness, delegate to `Hephaestus.start_instance` |
| `resume/2` | `resume(value, event)` | Build ID, delegate to `Hephaestus.resume` |
| `get/1` | `get(value)` | Build ID, delegate to `Storage.get` |
| `list/1` | `list(filters \\ [])` | Delegate to `Storage.query` with workflow filter |
| `cancel/1` | `cancel(value)` | Build ID, validate cancellable status, change to `:cancelled` |

With `scope: :none`, only `start/2` and `list/1` are generated. `resume/2`, `get/1`, and `cancel/1` are **not generated** — they would be ambiguous with multiple instances sharing the same value. The caller uses `list/1` to find instances and operates via `MyApp.Hephaestus.resume/2` or `MyApp.Hephaestus.cancel/1` with the full composite ID (including the random suffix).

#### `cancel/1` behavior

Cancels an active workflow instance:

1. Builds the composite ID from value
2. Fetches the instance from Storage via `get/1`
3. Validates the instance is in a cancellable status (`:pending`, `:running`, or `:waiting`)
4. Updates the instance status to `:cancelled` via Storage

**Returns:**
- `:ok` — instance cancelled successfully
- `{:error, :not_found}` — no instance with that ID
- `{:error, :not_cancellable}` — instance is in `:completed`, `:failed`, or `:cancelled` status

#### Flow of a `start` call

```
IncorporationFlow.start("abc123", ctx)
  -> Hephaestus.Instances.lookup!()                              # discovers MyApp.Hephaestus
  -> Uniqueness.build_id(unique, "abc123")                        # -> "blueprintid::abc123"
  -> Uniqueness.check(unique, id, workflow, version, query_fn)    # queries storage by scope
  -> MyApp.Hephaestus.start_instance(workflow, ctx, id: id)       # delegates to runner with custom ID
  -> {:ok, "blueprintid::abc123"}                                 # returns the composite ID
```

For `scope: :none`, `build_id_with_suffix/2` is used instead, and `check/5` is skipped:

```
NotificationFlow.start("abc123", ctx)
  -> Uniqueness.build_id_with_suffix(unique, "abc123")    # -> "userid::abc123::a1b2c3d4"
  -> MyApp.Hephaestus.start_instance(workflow, ctx, id: id)
  -> {:ok, "userid::abc123::a1b2c3d4"}
```

#### Where they live

- **Umbrella workflows:** facade lives in the umbrella module only. Version modules (V1, V2) only define `start/0`, `transit/3`, `events/0`.
- **Standalone workflows:** the module is both definition and facade.

#### Hephaestus module discovery

Facade functions call `Hephaestus.Instances.lookup!/0` internally. If `hephaestus:` is passed in the `use` options, it's used directly (for the rare multi-instance case).

### 4. Hephaestus.Instances — auto-discovery via Registry

Allows workflows to find the Hephaestus module without explicit configuration.

#### Architecture

Uses Elixir's `Registry` (same pattern as Oban). A Tracker process in the Hephaestus supervision tree registers on boot. When it dies, Registry cleans up automatically.

#### Hephaestus.Instances module

```elixir
defmodule Hephaestus.Instances do
  @registry __MODULE__.Registry

  def child_spec(_arg) do
    [keys: :unique, name: @registry]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: @registry)
  end

  def register(hephaestus_module) do
    Registry.register(@registry, hephaestus_module, :ok)
  end

  def lookup! do
    case Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [single] -> single
      [] -> raise "No Hephaestus instance running. Start one in your supervision tree."
      multiple -> raise "Multiple Hephaestus instances: #{inspect(multiple)}. " <>
                        "Pass hephaestus: MyApp.Hephaestus in your workflow's use options."
    end
  end
end
```

#### Tracker process

```elixir
defmodule Hephaestus.Instances.Tracker do
  use GenServer

  def start_link(hephaestus_module) do
    GenServer.start_link(__MODULE__, hephaestus_module)
  end

  def init(hephaestus_module) do
    Hephaestus.Instances.register(hephaestus_module)
    {:ok, hephaestus_module}
  end
end
```

#### Application

The `hephaestus_core` package gains an Application module to start the global Registry:

```elixir
defmodule Hephaestus.Application do
  use Application

  def start(_type, _args) do
    children = [Hephaestus.Instances]
    Supervisor.start_link(children, strategy: :one_for_one, name: Hephaestus.Supervisor)
  end
end
```

Each `MyApp.Hephaestus` adds the Tracker as a child:

```elixir
children = [
  {Registry, keys: :unique, name: registry},
  {DynamicSupervisor, ...},
  {Task.Supervisor, ...},
  {@hephaestus_storage_module, ...},
  {Hephaestus.Instances.Tracker, __MODULE__}
]
```

#### Explicit fallback

When multiple instances exist, the workflow declares which to use:

```elixir
use Hephaestus.Workflow,
  unique: [key: "blueprintid"],
  hephaestus: MyApp.Hephaestus
```

### 5. Changes to Instance and Storage

#### Instance.new — explicit ID

The constructor that auto-generates UUIDs is removed. All instances receive an explicit ID:

```elixir
def new(workflow, version, context, id) when is_binary(id) do
  %__MODULE__{
    id: id,
    workflow: workflow,
    workflow_version: version,
    context: Context.new(context)
  }
end
```

**Removed:** `new/1`, `new/2`, `new/3` (all auto-generated UUID). The private `generate_uuid/0` helper is also removed. Only `new/4` with explicit ID remains. No deprecation — no external users yet.

#### Storage behaviour — new filters

The `query/1` callback gains support for additional filters:

| Filter | Type | Purpose |
|---|---|---|
| `:id` | `String.t()` | Uniqueness check — exact ID match |
| `:workflow` | `module()` | Scope `:workflow` — filter by workflow module (already exists) |
| `:workflow_version` | `pos_integer()` | Scope `:version` — filter by version |
| `:status_in` | `[status()]` | Filter active instances `[:pending, :running, :waiting]` |

The `query/1` callback already exists in the Storage behaviour (accepts `:status` and `:workflow` filters). This extends it with additional filter keys — no new callback needed.

#### Storage.ETS — filter implementation

```elixir
defp match_filter?({:id, id}, instance), do: instance.id == id
defp match_filter?({:workflow, mod}, instance), do: instance.workflow == mod
defp match_filter?({:workflow_version, v}, instance), do: instance.workflow_version == v
defp match_filter?({:status_in, statuses}, instance), do: instance.status in statuses
```

### 6. Changes to Hephaestus entry-point macro

#### Tracker in supervision tree

```elixir
children = [
  # ... existing children ...
  {Hephaestus.Instances.Tracker, __MODULE__}
]
```

#### start_instance accepts custom ID

```elixir
def start_instance(workflow, context, opts \\ []) do
  id = Keyword.fetch!(opts, :id)

  {version, resolved_module} = resolve_version(workflow, opts)
  telemetry_metadata = Keyword.get(opts, :telemetry_metadata, %{})

  @hephaestus_runner_module.start_instance(
    resolved_module,
    context,
    Keyword.merge(runner_opts(),
      id: id,
      telemetry_metadata: telemetry_metadata,
      workflow_version: version
    )
  )
end
```

#### resume/2 unchanged

Continues receiving the full composite ID string. The workflow facade constructs the ID and calls `MyApp.Hephaestus.resume("blueprintid::abc123", :finalized)`.

### 7. Impact on extensions

#### hephaestus_ecto (0.1.0 -> 0.2.0)

- **Storage filters:** Support `:id`, `:workflow_version`, `:status_in` in query. Maps to SQL `WHERE` clauses. No schema change — `workflow_instances` table already has `id` (string), `workflow`, `workflow_version`, `status` columns.
- **Runner:** Accept `id:` in opts, pass to `Instance.new/4`.

#### hephaestus_oban (0.3.0 -> 0.4.0)

- **Storage filters:** Same as Ecto — queries `workflow_instances` table.
- **Runner:** Accept `id:` in opts, propagate to `Instance.new/4`. Worker args already carry `instance_id` as string — no change needed there.
- **Advisory lock for uniqueness check:** The check-and-create sequence is not atomic. In multi-node environments, two nodes may check simultaneously, both see "not found", and both create. The Oban runner wraps the uniqueness check + insert in a transaction with advisory lock:

```sql
SELECT pg_advisory_xact_lock(hashtext('blueprintid::abc123'));
-- check: SELECT ... WHERE id = 'blueprintid::abc123' AND status IN (...)
-- insert: INSERT INTO workflow_instances ...
```

This is the runner's responsibility, not the Uniqueness module's.

#### Release coordination

| Package | Current | New | Depends on |
|---|---|---|---|
| hephaestus_core | 0.1.5 | 0.2.0 | — |
| hephaestus_ecto | 0.1.0 | 0.2.0 | core ~> 0.2.0 |
| hephaestus_oban | 0.3.0 | 0.4.0 | core ~> 0.2.0, ecto ~> 0.2.0 |

Release order: core -> ecto -> oban.

### 8. Breaking changes

| What changes | Before | After |
|---|---|---|
| `Instance.new` | Auto-generates UUID | Receives explicit ID, UUID removed |
| `unique` in workflow | Did not exist | Mandatory |
| `start_instance` | `(workflow, context)` | `(workflow, context, id: "...")` required |
| `Instance.id` format | UUID v4 | `"key::value"` |

No deprecation warnings — no external users yet.

## References

- **Temporal:** Workflow ID is caller-provided business key. Workflow Id Reuse Policy and Conflict Policy control uniqueness. Signals use the business ID directly.
- **Camunda 8:** Process instance tags with `key:value` pattern for cross-system correlation. Immutable after creation.
- **AWS Step Functions:** Execution `name` is unique per state machine. Idempotent start returns existing execution.
- **Oban Pro Workflows:** `workflow_id` accepts custom string. Default UUIDv7 but customizable.
- **Oban Registry:** Uses Elixir `Registry` for instance discovery — same pattern adopted for `Hephaestus.Instances`.
