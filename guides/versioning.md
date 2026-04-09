# Workflow Versioning

Hephaestus supports workflow versioning out of the box. Different versions of the same workflow can coexist at runtime, allowing you to evolve workflows in production without breaking instances that are already executing.

Versions are sequential positive integers. Each version is a complete, independent Elixir module. An optional "umbrella" module acts as a dispatcher, mapping version numbers to concrete version modules.

## Implicit Versioning

Every workflow has a version --- even without an explicit declaration. A plain workflow is implicitly version `1`:

```elixir
defmodule MyApp.Workflows.SimpleFlow do
  use Hephaestus.Workflow

  def start, do: MyApp.Steps.ValidateInput

  def transit(MyApp.Steps.ValidateInput, :valid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.ValidateInput, :invalid, _ctx), do: Hephaestus.Steps.Done
end

MyApp.Workflows.SimpleFlow.__version__()    #=> 1
MyApp.Workflows.SimpleFlow.__versioned__?() #=> false
```

This means `Instance` always carries a `workflow_version` field, `start_instance` always resolves a version, and telemetry always emits version information. No conditional logic, no special cases.

## Creating Versioned Workflows

When a workflow needs to evolve, create separate version modules and an umbrella module to dispatch between them.

### Step 1: Define version modules

Each version is a standalone workflow with the `version:` option:

```elixir
defmodule MyApp.Workflows.CreateUser.V1 do
  use Hephaestus.Workflow, version: 1

  def start, do: MyApp.Steps.ValidateInput

  def transit(MyApp.Steps.ValidateInput, :valid, _ctx), do: MyApp.Steps.CreateRecord
  def transit(MyApp.Steps.ValidateInput, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.CreateRecord, :created, _ctx), do: Hephaestus.Steps.Done
end

defmodule MyApp.Workflows.CreateUser.V2 do
  use Hephaestus.Workflow, version: 2

  def start, do: MyApp.Steps.ValidateInput

  def transit(MyApp.Steps.ValidateInput, :valid, _ctx), do: MyApp.Steps.CreateRecord
  def transit(MyApp.Steps.ValidateInput, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.CreateRecord, :created, _ctx), do: MyApp.Steps.EnrichProfile
  def transit(MyApp.Steps.EnrichProfile, :enriched, _ctx), do: MyApp.Steps.SendWelcomeEmail
  def transit(MyApp.Steps.SendWelcomeEmail, :sent, _ctx), do: Hephaestus.Steps.Done
end
```

Each version module is a fully valid workflow with its own DAG, its own `start/0`, and its own `transit/3` clauses. Steps can be shared across versions --- they are plain modules.

### Step 2: Define the umbrella module

The umbrella module registers the version map and the compile-time default:

```elixir
defmodule MyApp.Workflows.CreateUser do
  use Hephaestus.Workflow,
    versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
    current: 2
end
```

The umbrella does not define `start/0` or `transit/3`. It generates dispatcher functions instead:

| Function | Description |
|---|---|
| `__versions__/0` | Returns the `%{integer => module}` version map |
| `__versioned__?/0` | Returns `true` |
| `current_version/0` | Returns the compile-time default version number |
| `resolve_version/1` | Maps a version integer (or `nil`) to `{version, module}` |
| `version_for/2` | Overridable callback for dynamic version resolution |

### Step 3: Start instances through the umbrella

```elixir
# Uses the compile-time default (V2)
{:ok, id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Joao", email: "joao@example.com"}
)

# Explicit version override
{:ok, id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Maria", email: "maria@example.com"},
  version: 1
)
```

### Compile-time validations

The umbrella module enforces these rules at compile time:

1. All keys in `versions` are positive integers.
2. All referenced modules implement the `Hephaestus.Core.Workflow` behaviour.
3. Each module's `__version__/0` matches its key in the `versions` map.
4. `current` is a key present in the `versions` map.
5. Version modules are nested under the umbrella module namespace (e.g., `CreateUser.V1`, `CreateUser.V2`).

## Dynamic Version Resolution

The umbrella module supports a three-step resolution chain when `start_instance/3` is called:

1. **Explicit** --- `opts[:version]` if the caller passes `version: N`.
2. **Dynamic callback** --- `version_for/2` if the umbrella overrides it.
3. **Compile default** --- `current_version/0` as the final fallback.

Override `version_for/2` in the umbrella module to implement runtime routing logic. The callback receives two arguments:

- `versions` --- the `%{integer => module}` map (same as `__versions__/0`)
- `opts` --- the keyword list passed to `start_instance/3`, forwarded as-is

Return an integer to select that version, or `nil` to fall through to the compile default.

### Tenant-based routing

```elixir
defmodule MyApp.Workflows.OnboardFlow do
  use Hephaestus.Workflow,
    versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
    current: 2

  def version_for(_versions, opts) do
    case opts[:tenant] do
      "legacy-corp" -> 1
      _ -> nil  # falls through to compile default (2)
    end
  end
end

# "legacy-corp" gets V1, everyone else gets V2
MyApp.Hephaestus.start_instance(OnboardFlow, context, tenant: "legacy-corp")
MyApp.Hephaestus.start_instance(OnboardFlow, context, tenant: "acme-inc")
```

### Canary deployments with feature flags

Use `version_for/2` together with a feature flag library like [fun_with_flags](https://hex.pm/packages/fun_with_flags) for gradual rollouts:

```elixir
defmodule MyApp.Workflows.CreateUser do
  use Hephaestus.Workflow,
    versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
    current: 1

  def version_for(%{2 => _}, opts) do
    if FunWithFlags.enabled?(:create_user_v2, for: opts[:actor]) do
      2
    end
  end

  def version_for(_, _), do: nil
end

# The actor is passed through opts and available in version_for/2
MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Pedro"},
  actor: current_user
)
```

The pattern-match on `%{2 => _}` is a safety guard --- if V2 is ever removed from the versions map, the clause simply does not match and the default version is used.

## Snapshot-at-Start Semantics

When an instance starts, the version is resolved once and the concrete module atom is stored on the `Instance` struct. From that point forward, the instance always uses that module --- even if the umbrella's `current:` changes in a later deploy.

```
t=0  start_instance(CreateUser, ctx)
     -> resolves current=2 -> Instance{workflow: CreateUser.V2, workflow_version: 2}

t=1  Deploy changes umbrella to current: 3

t=2  Engine advances the V2 instance -> calls CreateUser.V2.transit(...) -- unaffected

t=3  Resume from storage -> workflow: CreateUser.V2 -- still V2

t=4  New start_instance -> resolves to V3
```

This gives you safe, zero-downtime deployments. Old instances drain on their original version while new instances pick up the latest.

### Constraint: keep old version modules deployed

Version modules must remain in the codebase while instances of that version may still be active. The BEAM keeps old modules loaded in memory, but a hot code reload that removes a module will break any running instance that references it.

In practice, this means:

- **Do not delete** version module files until you are certain no instances of that version are running or stored.
- If you use `hephaestus_ecto`, you can query for active instances of a specific version before removing the module:

```elixir
# Check before removing V1
HephaestusEcto.Storage.query(
  workflow: MyApp.Workflows.CreateUser.V1,
  status: :running
)
```

## Telemetry

The `workflow_version` field is included in all 11 telemetry events automatically. You can use it to build version-aware dashboards and alerts:

```elixir
:telemetry.attach(
  "version-tracker",
  [:hephaestus, :workflow, :start],
  fn _event, _measurements, metadata, _config ->
    Logger.info("Started #{inspect(metadata.workflow)} v#{metadata.workflow_version}")
  end,
  nil
)
```

See the [Telemetry guide](telemetry.md) for the full event reference.

## Introspection

All version-related functions are available at runtime for inspection and tooling:

```elixir
# Umbrella module
MyApp.Workflows.CreateUser.__versions__()       #=> %{1 => ...V1, 2 => ...V2}
MyApp.Workflows.CreateUser.__versioned__?()     #=> true
MyApp.Workflows.CreateUser.current_version()    #=> 2

# Version module
MyApp.Workflows.CreateUser.V2.__version__()     #=> 2
MyApp.Workflows.CreateUser.V2.__versioned__?()  #=> false
MyApp.Workflows.CreateUser.V2.__graph__()       #=> %Graph{...}

# Resolution
MyApp.Workflows.CreateUser.resolve_version(1)   #=> {1, MyApp.Workflows.CreateUser.V1}
MyApp.Workflows.CreateUser.resolve_version(nil)  #=> {2, MyApp.Workflows.CreateUser.V2}
```

## Complete Example

Here is a full working example that ties everything together:

```elixir
# ==== Steps (shared across versions) ====

defmodule MyApp.Steps.ValidateInput do
  @behaviour Hephaestus.Steps.Step

  def events, do: [:valid, :invalid]

  def execute(_instance, _config, context) do
    case validate(context.initial) do
      :ok -> {:ok, :valid, %{validated_at: DateTime.utc_now()}}
      {:error, reason} -> {:ok, :invalid, %{error: reason}}
    end
  end

  defp validate(%{name: name}) when byte_size(name) > 0, do: :ok
  defp validate(_), do: {:error, "name is required"}
end

defmodule MyApp.Steps.CreateRecord do
  @behaviour Hephaestus.Steps.Step
  def events, do: [:created]

  def execute(_instance, _config, context) do
    user = MyApp.Users.create!(context.initial)
    {:ok, :created, %{user_id: user.id}}
  end
end

defmodule MyApp.Steps.EnrichProfile do
  @behaviour Hephaestus.Steps.Step
  def events, do: [:enriched]

  def execute(_instance, _config, context) do
    profile = MyApp.Enrichment.fetch(context.steps.create_record.user_id)
    {:ok, :enriched, %{profile: profile}}
  end
end

defmodule MyApp.Steps.SendWelcomeEmail do
  @behaviour Hephaestus.Steps.Step
  def events, do: [:sent]

  def execute(_instance, _config, context) do
    MyApp.Mailer.send_welcome(context.steps.create_record.user_id)
    {:ok, :sent, %{email_sent_at: DateTime.utc_now()}}
  end
end

# ==== Workflow Versions ====

defmodule MyApp.Workflows.CreateUser.V1 do
  use Hephaestus.Workflow, version: 1

  def start, do: MyApp.Steps.ValidateInput

  def transit(MyApp.Steps.ValidateInput, :valid, _ctx), do: MyApp.Steps.CreateRecord
  def transit(MyApp.Steps.ValidateInput, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.CreateRecord, :created, _ctx), do: Hephaestus.Steps.Done
end

defmodule MyApp.Workflows.CreateUser.V2 do
  use Hephaestus.Workflow, version: 2

  def start, do: MyApp.Steps.ValidateInput

  def transit(MyApp.Steps.ValidateInput, :valid, _ctx), do: MyApp.Steps.CreateRecord
  def transit(MyApp.Steps.ValidateInput, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(MyApp.Steps.CreateRecord, :created, _ctx), do: MyApp.Steps.EnrichProfile
  def transit(MyApp.Steps.EnrichProfile, :enriched, _ctx), do: MyApp.Steps.SendWelcomeEmail
  def transit(MyApp.Steps.SendWelcomeEmail, :sent, _ctx), do: Hephaestus.Steps.Done
end

# ==== Umbrella (dispatcher) ====

defmodule MyApp.Workflows.CreateUser do
  use Hephaestus.Workflow,
    versions: %{1 => __MODULE__.V1, 2 => __MODULE__.V2},
    current: 2

  # Optional: canary rollout via feature flags
  def version_for(%{2 => _}, opts) do
    if FunWithFlags.enabled?(:create_user_v2, for: opts[:actor]) do
      2
    end
  end

  def version_for(_, _), do: nil
end

# ==== Application Usage ====

# Compile default (V2)
{:ok, id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Joao", email: "joao@example.com"}
)

# Explicit version
{:ok, id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Maria", email: "maria@example.com"},
  version: 1
)

# Dynamic resolution via actor (version_for/2 decides)
{:ok, id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.CreateUser,
  %{name: "Pedro", email: "pedro@example.com"},
  actor: current_user
)
```
