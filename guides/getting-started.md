# Getting Started

This guide walks you through installing Hephaestus, defining steps, building a workflow, and running it.

## Prerequisites

- Elixir 1.19+
- An existing Elixir application

## Step 1: Install Hephaestus

Add `hephaestus` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:hephaestus, "~> 0.2.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Step 2: Define your steps

Every step implements the `Hephaestus.Steps.Step` behaviour. A step declares the events it can emit and an `execute/3` callback that returns one of them.

```elixir
defmodule MyApp.Steps.ValidateOrder do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:valid, :invalid]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:items] && length(context.initial.items) > 0 do
      {:ok, :valid, %{item_count: length(context.initial.items)}}
    else
      {:ok, :invalid}
    end
  end
end
```

Return values from `execute/3`:

- `{:ok, event}` — step completed, emit the named event
- `{:ok, event, context_updates}` — completed with data to store in context
- `{:async}` — step is async, workflow pauses until resumed
- `{:error, reason}` — step failed

## Step 3: Define a workflow

A workflow declares the starting step and transitions between steps using pattern matching. Use `use Hephaestus.Workflow` and implement `start/0` and `transit/3`:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow

  alias MyApp.Steps.{ValidateOrder, ChargePayment, SendConfirmation}

  @impl true
  def start, do: ValidateOrder

  @impl true
  def transit(ValidateOrder, :valid, _ctx), do: ChargePayment
  def transit(ValidateOrder, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(ChargePayment, :charged, _ctx), do: SendConfirmation
  def transit(SendConfirmation, :sent, _ctx), do: Hephaestus.Steps.Done
end
```

Every path must end at `Hephaestus.Steps.Done`. The workflow DAG is validated at compile time — cycles, unreachable steps, and missing transitions all raise `CompileError`.

### Tags and metadata (optional)

Workflows can declare tags and metadata for observability. Runner adapters (like `hephaestus_oban`) use these to tag jobs for filtering and grouping:

```elixir
defmodule MyApp.Workflows.OrderFlow do
  use Hephaestus.Workflow,
    tags: ["orders", "checkout"],
    metadata: %{"team" => "payments", "priority" => "high"}

  # ... start/0 and transit/3 as before
end
```

- `:tags` — list of strings (default: `[]`)
- `:metadata` — map with string keys and JSON-safe values (default: `%{}`)

Both are accessible at runtime via `MyApp.Workflows.OrderFlow.__tags__()` and `MyApp.Workflows.OrderFlow.__metadata__()`. Invalid inputs (atom keys, non-JSON-safe values) raise `CompileError`.

## Step 4: Set up the supervision tree

Create an entry module using `use Hephaestus` and add it to your application's supervision tree:

```elixir
defmodule MyApp.Hephaestus do
  use Hephaestus,
    storage: Hephaestus.Runtime.Storage.ETS,
    runner: Hephaestus.Runtime.Runner.Local
end
```

In your `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Hephaestus
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

This starts a Registry, DynamicSupervisor, TaskSupervisor, and the ETS storage adapter under a single supervisor.

## Step 5: Run a workflow

```elixir
{:ok, instance_id} = MyApp.Hephaestus.start_instance(
  MyApp.Workflows.OrderFlow,
  %{items: ["widget", "gadget"]}
)
```

The second argument is the initial context — it's available to all steps via `context.initial`.

If you later introduce workflow versioning, `start_instance/3` also accepts
`version: <positive_integer>` for an explicit version override.

## Handling async steps and resume

Steps that return `{:async}` pause the workflow in `:waiting` status. Resume them with an event:

```elixir
defmodule MyApp.Steps.WaitForPayment do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:payment_confirmed]

  @impl true
  def execute(_instance, _config, _context), do: {:async}
end
```

In your workflow:

```elixir
def transit(WaitForPayment, :payment_confirmed, _ctx), do: FulfillOrder
```

When the external event arrives (webhook, message, etc.), resume the instance:

```elixir
:ok = MyApp.Hephaestus.resume(instance_id, :payment_confirmed)
```

The workflow picks up from where it paused and continues executing.

## Built-in steps

Hephaestus ships with four built-in steps:

| Step | Purpose | Returns |
|------|---------|---------|
| `Hephaestus.Steps.Done` | Terminal step — every workflow path must end here | `{:ok, :done}` |
| `Hephaestus.Steps.Wait` | Pauses for a configured duration | `{:async}` (emits `:timeout`) |
| `Hephaestus.Steps.WaitForEvent` | Pauses until an external event resumes it | `{:async}` (emits `:received`) |
| `Hephaestus.Steps.Debug` | Logs context and execution history | `{:ok, :completed}` |

`Wait` accepts a config map with `:duration` and `:unit`:

```elixir
def start, do: {Hephaestus.Steps.Wait, %{duration: 5, unit: :minute}}
```

`Debug` can be inserted anywhere during development to inspect accumulated state.

## Complete example

Here's a working 3-step workflow: validate an order, process payment, then complete.

```elixir
# lib/my_app/steps/validate.ex
defmodule MyApp.Steps.Validate do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:ok, :invalid]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:amount] && context.initial.amount > 0 do
      {:ok, :ok, %{validated_at: DateTime.utc_now()}}
    else
      {:ok, :invalid}
    end
  end
end

# lib/my_app/steps/process_payment.ex
defmodule MyApp.Steps.ProcessPayment do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:charged]

  @impl true
  def execute(_instance, _config, context) do
    amount = context.initial.amount
    {:ok, :charged, %{amount_charged: amount}}
  end
end

# lib/my_app/steps/notify.ex
defmodule MyApp.Steps.Notify do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:sent]

  @impl true
  def execute(_instance, _config, context) do
    IO.puts("Payment of #{context.steps.process_payment.amount_charged} processed!")
    {:ok, :sent}
  end
end

# lib/my_app/workflows/checkout.ex
defmodule MyApp.Workflows.Checkout do
  use Hephaestus.Workflow

  alias MyApp.Steps.{Validate, ProcessPayment, Notify}

  @impl true
  def start, do: Validate

  @impl true
  def transit(Validate, :ok, _ctx), do: ProcessPayment
  def transit(Validate, :invalid, _ctx), do: Hephaestus.Steps.Done
  def transit(ProcessPayment, :charged, _ctx), do: Notify
  def transit(Notify, :sent, _ctx), do: Hephaestus.Steps.Done
end

# lib/my_app/hephaestus.ex
defmodule MyApp.Hephaestus do
  use Hephaestus
end
```

Run it:

```elixir
{:ok, id} = MyApp.Hephaestus.start_instance(MyApp.Workflows.Checkout, %{amount: 4999})
# => "Payment of 4999 processed!"
```

## Context

Each step receives a `Hephaestus.Core.Context` struct with two fields:

- `context.initial` — the map passed to `start_instance/2`, immutable
- `context.steps` — results from completed steps, keyed by step name (e.g., `context.steps.validate`)

Step names are derived from the last segment of the module name, underscored. `MyApp.Steps.ProcessPayment` becomes `:process_payment`. Override this with the optional `step_key/0` callback.

## Next steps

- Browse the [HexDocs](https://hexdocs.pm/hephaestus) for full API reference
- Read the source for `Hephaestus.Core.Engine` to understand the execution model
- Check `Hephaestus.Steps.Step` for the complete behaviour specification
