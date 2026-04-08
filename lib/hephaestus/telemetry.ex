defmodule Hephaestus.Telemetry do
  @moduledoc """
  Telemetry event emission for Hephaestus workflow and step lifecycle.

  This module provides helper functions that Runner implementations call to emit
  `:telemetry` events at every significant lifecycle point. Using these helpers
  (rather than calling `:telemetry.execute/3` directly) ensures consistent event
  names, measurements, and metadata across all runners (Local, Oban, custom).

  ## Events

  Hephaestus emits 11 events organized in two spans and five standalone events:

  ### Workflow Span

    * `[:hephaestus, :workflow, :start]` --- workflow instance created
    * `[:hephaestus, :workflow, :stop]` --- workflow completed successfully
    * `[:hephaestus, :workflow, :exception]` --- workflow failed

  ### Step Span

    * `[:hephaestus, :step, :start]` --- step execution begins
    * `[:hephaestus, :step, :stop]` --- step completed successfully
    * `[:hephaestus, :step, :exception]` --- step failed or raised

  ### Standalone

    * `[:hephaestus, :step, :async]` --- step returned `{:async}`
    * `[:hephaestus, :step, :resume]` --- async step resumed
    * `[:hephaestus, :workflow, :transition]` --- engine activated next steps
    * `[:hephaestus, :engine, :advance]` --- engine advance tick
    * `[:hephaestus, :runner, :init]` --- runner supervision tree started

  ## API Stability

  Event names and metadata structure are public API. Patch versions only add
  fields, never remove or rename. See the [Telemetry guide](telemetry.md) for
  full details.
  """

  alias Hephaestus.Core.Instance

  @workflow_start_event [:hephaestus, :workflow, :start]
  @workflow_stop_event [:hephaestus, :workflow, :stop]
  @workflow_exception_event [:hephaestus, :workflow, :exception]
  @workflow_transition_event [:hephaestus, :workflow, :transition]
  @step_start_event [:hephaestus, :step, :start]
  @step_stop_event [:hephaestus, :step, :stop]
  @step_exception_event [:hephaestus, :step, :exception]
  @step_async_event [:hephaestus, :step, :async]
  @step_resume_event [:hephaestus, :step, :resume]
  @engine_advance_event [:hephaestus, :engine, :advance]
  @runner_init_event [:hephaestus, :runner, :init]

  @type event_name :: [atom()]

  @doc "Returns the event name `[:hephaestus, :workflow, :start]`."
  @spec workflow_start_event() :: event_name()
  def workflow_start_event, do: @workflow_start_event

  @doc "Returns the event name `[:hephaestus, :workflow, :stop]`."
  @spec workflow_stop_event() :: event_name()
  def workflow_stop_event, do: @workflow_stop_event

  @doc "Returns the event name `[:hephaestus, :workflow, :exception]`."
  @spec workflow_exception_event() :: event_name()
  def workflow_exception_event, do: @workflow_exception_event

  @doc "Returns the event name `[:hephaestus, :workflow, :transition]`."
  @spec workflow_transition_event() :: event_name()
  def workflow_transition_event, do: @workflow_transition_event

  @doc "Returns the event name `[:hephaestus, :step, :start]`."
  @spec step_start_event() :: event_name()
  def step_start_event, do: @step_start_event

  @doc "Returns the event name `[:hephaestus, :step, :stop]`."
  @spec step_stop_event() :: event_name()
  def step_stop_event, do: @step_stop_event

  @doc "Returns the event name `[:hephaestus, :step, :exception]`."
  @spec step_exception_event() :: event_name()
  def step_exception_event, do: @step_exception_event

  @doc "Returns the event name `[:hephaestus, :step, :async]`."
  @spec step_async_event() :: event_name()
  def step_async_event, do: @step_async_event

  @doc "Returns the event name `[:hephaestus, :step, :resume]`."
  @spec step_resume_event() :: event_name()
  def step_resume_event, do: @step_resume_event

  @doc "Returns the event name `[:hephaestus, :engine, :advance]`."
  @spec engine_advance_event() :: event_name()
  def engine_advance_event, do: @engine_advance_event

  @doc "Returns the event name `[:hephaestus, :runner, :init]`."
  @spec runner_init_event() :: event_name()
  def runner_init_event, do: @runner_init_event

  @doc "Returns all 11 Hephaestus telemetry event names. Used by `LogHandler` to attach to all events."
  @spec events() :: [event_name()]
  def events do
    [
      workflow_start_event(),
      workflow_stop_event(),
      workflow_exception_event(),
      workflow_transition_event(),
      step_start_event(),
      step_stop_event(),
      step_exception_event(),
      step_async_event(),
      step_resume_event(),
      engine_advance_event(),
      runner_init_event()
    ]
  end

  @doc """
  Emits `[:hephaestus, :workflow, :start]` when a runner creates a new workflow instance.

  ## Measurements

    * `:system_time` --- wall-clock time from `System.system_time/0`

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * Plus any fields in `extra_metadata` (e.g., `:initial_step`, `:context_keys`, `:runner`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec workflow_start(Instance.t(), map()) :: :ok
  def workflow_start(instance, extra_metadata) do
    execute(
      workflow_start_event(),
      %{system_time: System.system_time()},
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow},
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :workflow, :stop]` when a workflow reaches `:completed` status.

  ## Measurements

    * `:duration` --- elapsed time in native units since workflow start (or `nil` after VM restart)
    * `:step_count` --- number of steps completed (extracted from `extra_metadata`)
    * `:advance_count` --- number of engine advance ticks (extracted from `extra_metadata`)

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:status` --- always `:completed`
    * Plus any additional fields in `extra_metadata` (e.g., `:completed_steps`, `:runner`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec workflow_stop(Instance.t(), map()) :: :ok
  def workflow_stop(instance, extra_metadata) do
    {measurements, metadata} = Map.split(extra_metadata, [:step_count, :advance_count])

    execute(
      workflow_stop_event(),
      Map.put(measurements, :duration, safe_duration(instance.telemetry_start_time)),
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow, status: :completed},
        metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :workflow, :exception]` when a workflow reaches `:failed` status.

  ## Measurements

    * `:duration` --- elapsed time in native units since workflow start (or `nil` after VM restart)

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:kind` --- `:error`, `:throw`, or `:exit`
    * `:reason` --- the error term
    * `:stacktrace` --- stacktrace list or `nil` if `{:error, reason}` return
    * `:status` --- always `:failed`
    * Plus any additional fields in `extra_metadata` (e.g., `:failed_step`, `:runner`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec workflow_exception(Instance.t(), atom(), term(), list() | nil, map()) :: :ok
  def workflow_exception(instance, kind, reason, stacktrace, extra_metadata) do
    execute(
      workflow_exception_event(),
      %{duration: safe_duration(instance.telemetry_start_time)},
      merge_instance_metadata(
        instance,
        %{
          instance_id: instance.id,
          workflow: instance.workflow,
          kind: kind,
          reason: reason,
          stacktrace: stacktrace,
          status: :failed
        },
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :step, :start]` before a step's `execute/3` callback is invoked.

  ## Measurements

    * `:system_time` --- wall-clock time from `System.system_time/0`

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:step` --- the step module being executed
    * Plus any additional fields in `extra_metadata` (e.g., `:step_key`, `:concurrent`, `:active_steps_count`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec step_start(Instance.t(), module(), map()) :: :ok
  def step_start(instance, step, extra_metadata) do
    execute(
      step_start_event(),
      %{system_time: System.system_time()},
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow, step: step},
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :step, :stop]` when a step returns `{:ok, event}` or `{:ok, event, updates}`.

  ## Measurements

    * `:duration` --- step execution time in native units

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:step` --- the step module that completed
    * Plus any additional fields in `extra_metadata` (e.g., `:step_key`, `:event`, `:has_context_updates`, `:transitions_to`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec step_stop(Instance.t(), module(), integer(), map()) :: :ok
  def step_stop(instance, step, duration, extra_metadata) do
    execute(
      step_stop_event(),
      %{duration: duration},
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow, step: step},
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :step, :exception]` when a step returns `{:error, reason}` or raises.

  ## Measurements

    * `:duration` --- step execution time in native units

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:step` --- the step module that failed
    * `:kind` --- `:error`, `:throw`, or `:exit`
    * `:reason` --- the error term
    * `:stacktrace` --- stacktrace list or `nil`
    * Plus any additional fields in `extra_metadata` (e.g., `:step_key`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec step_exception(Instance.t(), module(), integer(), atom(), term(), list() | nil, map()) ::
          :ok
  def step_exception(instance, step, duration, kind, reason, stacktrace, extra_metadata) do
    execute(
      step_exception_event(),
      %{duration: duration},
      merge_instance_metadata(
        instance,
        %{
          instance_id: instance.id,
          workflow: instance.workflow,
          step: step,
          kind: kind,
          reason: reason,
          stacktrace: stacktrace
        },
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :step, :async]` when a step returns `{:async}`.

  ## Measurements

    * `:duration` --- step execution time in native units before going async

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:step` --- the step module that went async
    * Plus any additional fields in `extra_metadata` (e.g., `:step_key`, `:instance_status`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec step_async(Instance.t(), module(), integer(), map()) :: :ok
  def step_async(instance, step, duration, extra_metadata) do
    execute(
      step_async_event(),
      %{duration: duration},
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow, step: step},
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :step, :resume]` when an async step receives an external event or timeout.

  ## Measurements

    * `:system_time` --- wall-clock time from `System.system_time/0`
    * `:wait_duration` --- time spent waiting in native units (extracted from `extra_metadata`)

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:step` --- the step module being resumed
    * Plus any additional fields in `extra_metadata` (e.g., `:step_key`, `:resume_event`, `:source`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec step_resume(Instance.t(), module(), map()) :: :ok
  def step_resume(instance, step, extra_metadata) do
    {measurements, metadata} = Map.split(extra_metadata, [:wait_duration])

    execute(
      step_resume_event(),
      Map.put(measurements, :system_time, System.system_time()),
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow, step: step},
        metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :workflow, :transition]` when the engine activates next steps after a step completion.

  ## Measurements

    * `:targets_count` --- number of activated target steps

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * `:from_step` --- the step module that triggered the transition
    * `:event` --- the event atom returned by the step
    * `:targets` --- list of activated step modules
    * `:fan_out` --- `true` if `targets_count > 1`
    * Plus any additional fields in `extra_metadata`
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec workflow_transition(Instance.t(), module(), atom(), [module()], map()) :: :ok
  def workflow_transition(instance, from_step, event, targets, extra_metadata) do
    execute(
      workflow_transition_event(),
      %{targets_count: length(targets)},
      merge_instance_metadata(
        instance,
        %{
          instance_id: instance.id,
          workflow: instance.workflow,
          from_step: from_step,
          event: event,
          targets: targets,
          fan_out: length(targets) > 1
        },
        extra_metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :engine, :advance]` on each `Engine.advance/1` call by the runner.

  ## Measurements

    * `:duration` --- advance tick execution time in native units
    * `:active_steps_count` --- number of currently active steps (extracted from `extra_metadata`)
    * `:completed_in_advance` --- steps completed in this advance tick (extracted from `extra_metadata`)

  ## Metadata

    * `:instance_id` --- unique identifier for the workflow instance
    * `:workflow` --- the workflow module
    * Plus any additional fields in `extra_metadata` (e.g., `:status_before`, `:status_after`, `:iteration`)
    * Plus caller-supplied `telemetry_metadata` from the instance
  """
  @spec engine_advance(Instance.t(), integer(), map()) :: :ok
  def engine_advance(instance, duration, extra_metadata) do
    {measurements, metadata} =
      Map.split(extra_metadata, [:active_steps_count, :completed_in_advance])

    execute(
      engine_advance_event(),
      Map.put(measurements, :duration, duration),
      merge_instance_metadata(
        instance,
        %{instance_id: instance.id, workflow: instance.workflow},
        metadata
      )
    )
  end

  @doc """
  Emits `[:hephaestus, :runner, :init]` when the Hephaestus supervision tree starts.

  ## Measurements

    * `:system_time` --- wall-clock time from `System.system_time/0`

  ## Metadata

    * `:name` --- registered name of the runner
    * `:runner` --- the runner module
    * `:storage` --- the storage module
    * `:pid` --- PID of the runner process
  """
  @spec runner_init(map()) :: :ok
  def runner_init(extra_metadata) do
    execute(
      runner_init_event(),
      %{system_time: System.system_time()},
      extra_metadata
    )
  end

  defp execute(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  defp merge_instance_metadata(instance, hephaestus_fields, extra_metadata) do
    instance.telemetry_metadata
    |> Map.merge(extra_metadata)
    |> Map.merge(hephaestus_fields)
  end

  defp safe_duration(nil), do: nil

  defp safe_duration(start_time) do
    duration = System.monotonic_time() - start_time

    if duration >= 0, do: duration, else: nil
  end
end
