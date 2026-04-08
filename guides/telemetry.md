# Telemetry

Hephaestus emits [`:telemetry`](https://hexdocs.pm/telemetry) events at every significant point in workflow and step execution. These events let you observe, measure, and react to workflow behavior without modifying your business logic.

Events are always emitted (the overhead is ~1-2 microseconds with no handler attached). Handlers are opt-in --- you attach only what you need.

## Quick Start

### 1. Upgrade your dependency

Hephaestus includes `:telemetry` automatically. No extra dependencies are needed.

```elixir
def deps do
  [
    {:hephaestus, "~> 0.1.5"}
  ]
end
```

### 2. Attach the built-in log handler

In your `application.ex` start callback, add:

```elixir
def start(_type, _args) do
  Hephaestus.Telemetry.LogHandler.attach()

  children = [
    MyApp.Hephaestus
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 3. See structured log output

Run a workflow and you will see output like:

```
[info] [abc-123] Workflow started
[info] [abc-123] Step MyApp.Steps.Validate started
[info] [abc-123] Step MyApp.Steps.Validate completed in 2ms -> :ok
[debug] [abc-123] Transition: MyApp.Steps.Validate -> MyApp.Steps.ProcessPayment
[info] [abc-123] Workflow completed in 15ms
```

Every log line includes the `instance_id` as a prefix and structured metadata fields (`workflow`, `step`, `duration_ms`) for machine parsing.

## Events Reference

Hephaestus emits 11 events organized into two spans and five standalone events.

### Workflow Span

| Event Name | Measurements | Metadata |
|---|---|---|
| `[:hephaestus, :workflow, :start]` | `system_time` | `instance_id`, `workflow`, `initial_step`, `context_keys`, `runner` |
| `[:hephaestus, :workflow, :stop]` | `duration`, `step_count`, `advance_count` | `instance_id`, `workflow`, `status` (`:completed`), `completed_steps`, `runner` |
| `[:hephaestus, :workflow, :exception]` | `duration`, `step_count`, `advance_count` | `instance_id`, `workflow`, `status` (`:failed`), `failed_step`, `reason`, `kind`, `stacktrace`, `runner` |

### Step Span

| Event Name | Measurements | Metadata |
|---|---|---|
| `[:hephaestus, :step, :start]` | `system_time` | `instance_id`, `workflow`, `step`, `step_key`, `concurrent`, `active_steps_count` |
| `[:hephaestus, :step, :stop]` | `duration` | `instance_id`, `workflow`, `step`, `step_key`, `event`, `has_context_updates`, `has_metadata_updates`, `transitions_to` |
| `[:hephaestus, :step, :exception]` | `duration` | `instance_id`, `workflow`, `step`, `step_key`, `kind`, `reason`, `stacktrace` |

### Standalone Events

| Event Name | Measurements | Metadata |
|---|---|---|
| `[:hephaestus, :step, :async]` | `duration` | `instance_id`, `workflow`, `step`, `step_key`, `instance_status` (`:waiting`) |
| `[:hephaestus, :step, :resume]` | `system_time`, `wait_duration` | `instance_id`, `workflow`, `step`, `step_key`, `resume_event`, `source` |
| `[:hephaestus, :workflow, :transition]` | `system_time`, `targets_count` | `instance_id`, `workflow`, `from_step`, `event`, `targets`, `fan_out` |
| `[:hephaestus, :engine, :advance]` | `duration`, `active_steps_count`, `completed_in_advance` | `instance_id`, `workflow`, `status_before`, `status_after`, `iteration` |
| `[:hephaestus, :runner, :init]` | `system_time` | `name`, `runner`, `storage`, `pid` |

All `duration` values are in Erlang native time units. Convert with `System.convert_time_unit(duration, :native, :millisecond)`.

## By Use Case

### I want to track failures

Attach a handler to `[:hephaestus, :workflow, :exception]` and `[:hephaestus, :step, :exception]`. The metadata includes `kind`, `reason`, and `stacktrace` for crash diagnostics, plus `failed_step` on the workflow event to identify which step caused the failure.

```elixir
:telemetry.attach(
  "my-failure-handler",
  [:hephaestus, :workflow, :exception],
  fn _event, _measurements, metadata, _config ->
    Logger.error("Workflow #{inspect(metadata.workflow)} failed at #{inspect(metadata.failed_step)}: #{inspect(metadata.reason)}")
  end,
  nil
)
```

### I want to measure latency

Use `[:hephaestus, :workflow, :stop]` for end-to-end workflow duration and `[:hephaestus, :step, :stop]` for individual step duration. Both include a `duration` measurement in native time units.

```elixir
:telemetry.attach(
  "my-latency-handler",
  [:hephaestus, :step, :stop],
  fn _event, measurements, metadata, _config ->
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    Logger.info("Step #{inspect(metadata.step)} took #{ms}ms")
  end,
  nil
)
```

### I want to monitor fan-out

The `[:hephaestus, :workflow, :transition]` event includes `fan_out: true` when a step triggers multiple concurrent targets. The `targets_count` measurement tells you the parallelism degree, and `targets` in metadata lists the activated step modules.

### I want to debug async steps

Two events cover the async lifecycle:

- `[:hephaestus, :step, :async]` --- emitted when a step returns `{:async}`, with `duration` measuring how long the step ran before going async.
- `[:hephaestus, :step, :resume]` --- emitted when the step receives an external event or timeout, with `wait_duration` measuring how long the workflow spent waiting and `source` indicating whether the resume was `:external` or `:timeout`.

## Log Handler

`Hephaestus.Telemetry.LogHandler` is a built-in handler that produces structured `Logger` output for all Hephaestus events.

### Attaching

```elixir
# Attach with defaults (all events, standard log levels)
Hephaestus.Telemetry.LogHandler.attach()

# Attach with custom options
Hephaestus.Telemetry.LogHandler.attach(
  level: %{[:hephaestus, :step, :stop] => :debug},
  events: [
    [:hephaestus, :workflow, :start],
    [:hephaestus, :workflow, :stop],
    [:hephaestus, :workflow, :exception]
  ]
)
```

### Detaching

```elixir
Hephaestus.Telemetry.LogHandler.detach()
```

### Default Log Levels

| Event | Level |
|---|---|
| `workflow:start` | `:info` |
| `workflow:stop` | `:info` |
| `workflow:exception` | `:error` |
| `workflow:transition` | `:debug` |
| `step:start` | `:info` |
| `step:stop` | `:info` |
| `step:exception` | `:error` |
| `step:async` | `:warning` |
| `step:resume` | `:info` |
| `engine:advance` | `:debug` |
| `runner:init` | `:info` |

Override any level by passing a `:level` map keyed by event name.

### Options

- `:level` --- a map of event name (list of atoms) to log level atom. Overrides the defaults above.
- `:events` --- a list of event names to subscribe to. Defaults to all events from `Hephaestus.Telemetry.events/0`.

## Metrics

`Hephaestus.Telemetry.Metrics` returns pre-built `Telemetry.Metrics` structs that plug directly into any reporter (Prometheus, StatsD, LiveDashboard).

```elixir
# In your application supervisor
metrics = Hephaestus.Telemetry.Metrics.metrics()

children = [
  {TelemetryMetricsPrometheus, metrics: metrics}
]
```

### Scope Filtering

Filter metrics by scope to include only what you need:

```elixir
Hephaestus.Telemetry.Metrics.metrics(scope: :workflow)  # workflow metrics only
Hephaestus.Telemetry.Metrics.metrics(scope: :step)      # step metrics only
Hephaestus.Telemetry.Metrics.metrics()                   # all metrics
```

### Metric Definitions

| Metric | Type | Tags |
|---|---|---|
| `hephaestus.workflow.start.count` | counter | `workflow` |
| `hephaestus.workflow.stop.count` | counter | `workflow` |
| `hephaestus.workflow.exception.count` | counter | `workflow`, `failed_step` |
| `hephaestus.workflow.stop.duration` | distribution | `workflow` |
| `hephaestus.step.stop.duration` | distribution | `workflow`, `step` |
| `hephaestus.step.exception.count` | counter | `workflow`, `step`, `kind` |
| `hephaestus.step.async.count` | counter | `workflow`, `step` |
| `hephaestus.step.resume.wait_duration` | distribution | `workflow`, `step`, `source` |
| `hephaestus.engine.advance.active_steps_count` | last_value | `workflow` |

## Custom Handlers

Use standard `:telemetry.attach/4` or `:telemetry.attach_many/4` to build your own handlers. Here is an example that sends Slack notifications on workflow failures:

```elixir
defmodule MyApp.Telemetry.SlackNotifier do
  def attach do
    :telemetry.attach(
      "slack-workflow-failure",
      [:hephaestus, :workflow, :exception],
      &handle_event/4,
      %{webhook_url: System.fetch_env!("SLACK_WEBHOOK_URL")}
    )
  end

  def handle_event(_event, measurements, metadata, config) do
    duration_ms =
      case measurements[:duration] do
        nil -> "unknown"
        d -> "#{System.convert_time_unit(d, :native, :millisecond)}ms"
      end

    message = """
    Workflow failed: #{inspect(metadata.workflow)}
    Step: #{inspect(metadata.failed_step)}
    Reason: #{inspect(metadata.reason)}
    Duration: #{duration_ms}
    Instance: #{metadata.instance_id}
    """

    HTTPClient.post(config.webhook_url, %{text: message})
  end
end
```

And an example for Sentry error reporting:

```elixir
:telemetry.attach(
  "sentry-step-exception",
  [:hephaestus, :step, :exception],
  fn _event, _measurements, metadata, _config ->
    if metadata[:stacktrace] do
      Sentry.capture_exception(metadata.reason,
        stacktrace: metadata.stacktrace,
        extra: %{
          workflow: inspect(metadata.workflow),
          step: inspect(metadata.step),
          instance_id: metadata.instance_id
        }
      )
    end
  end,
  nil
)
```

## Caller Metadata

When starting a workflow, you can pass a `telemetry_metadata` map that gets merged into every telemetry event from that instance. This is useful for correlating workflow events with application-level context such as request IDs, user IDs, or trace context.

```elixir
MyApp.Hephaestus.start_instance(
  MyApp.Workflows.OrderFlow,
  %{items: ["widget"]},
  telemetry_metadata: %{request_id: "req-abc-123", user_id: 42}
)
```

All 11 telemetry events from this instance will include `request_id: "req-abc-123"` and `user_id: 42` in their metadata. This works across process boundaries because the data lives on the `Instance` struct, not in the process dictionary.

### Constraints

- **Serializable values only**: No PIDs, references, or functions. Values must survive JSON serialization for future Oban runner support.
- **Lower precedence**: Caller-supplied fields are merged with lower precedence. You cannot override Hephaestus-defined fields like `instance_id`, `workflow`, or `step`.
- **No key validation**: Avoid using keys that conflict with Hephaestus metadata field names.

## API Stability

Event names and metadata structure are part of the public API. Changes follow semantic versioning:

- **Patch versions** (0.1.x): Only add new measurement or metadata fields. Never remove or rename existing fields.
- **Minor versions** (0.x.0): May deprecate fields with a warning for one minor version before removal.
- **Event names**: Event names like `[:hephaestus, :workflow, :start]` are never changed. New events may be added.

## Known Limitations

### Duration is invalid after VM restart

`duration` measurements use `System.monotonic_time/0`, which is relative to the current VM instance. If a workflow spans a VM restart (deploy, crash recovery), the stored start time becomes meaningless. In this case, `duration` is emitted as `nil`.

Handlers and metric reporters should handle `nil` durations gracefully. Long-running workflows that span deploys are better served by the Oban runner, which measures per-job durations independently.

### Step events run in the task process

Step telemetry events (`step:start`, `step:stop`, `step:exception`, `step:async`) are emitted inside the `Task.Supervisor` task process, not the Runner GenServer. Handlers that inspect `self()` or rely on the process dictionary will see the task context, not the GenServer context.

This is safe because the `:telemetry` library wraps handlers in `try/catch` --- a handler crash never propagates to the step execution. Standard handlers (Logger, Prometheus, StatsD) do not depend on `self()`. If your handler needs GenServer context, use `instance_id` from metadata for correlation.

### No Engine-level telemetry

The Engine is purely functional and emits no telemetry. Events are emitted from the Runtime layer (runners). Direct Engine usage in IEx or tests produces no telemetry output. This is intentional --- telemetry is a runtime concern.
