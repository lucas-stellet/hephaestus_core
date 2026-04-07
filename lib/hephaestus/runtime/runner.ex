defmodule Hephaestus.Runtime.Runner do
  @moduledoc """
  Execution adapter contract for workflow instances.
  """

  @doc """
  Starts a new workflow instance.

  Creates an instance for the given `workflow` module, initializes it with the
  provided `context`, and begins execution. The runner is responsible for
  persisting the instance and managing its lifecycle.

  ## Arguments

    * `workflow` — the workflow module to instantiate.
    * `context` — a map of initial data passed to the workflow steps.
    * `opts` — runner-specific options (e.g., storage adapter, registry, supervisors).

  ## Return

    * `{:ok, instance_id}` — the unique identifier assigned to the new instance.
    * `{:error, reason}` — if the instance could not be started.
  """
  @callback start_instance(
              workflow :: module(),
              context :: map(),
              opts :: keyword()
            ) :: {:ok, instance_id :: String.t()} | {:error, reason :: term()}

  @doc """
  Resumes a waiting workflow instance with the given event.

  Delivers `event` to the instance identified by `instance_id`, unblocking the
  step that is currently waiting. The runner re-enters the execution loop after
  the event is applied.

  ## Arguments

    * `instance_id` — the identifier of the instance to resume.
    * `event` — the event atom that satisfies the waiting condition.

  ## Return

    * `:ok` — the event was delivered successfully.
    * `{:error, reason}` — if the instance was not found or could not be resumed.
  """
  @callback resume(
              instance_id :: String.t(),
              event :: atom()
            ) :: :ok | {:error, reason :: term()}

  @doc """
  Schedules a delayed resume for a specific step.

  After `delay_ms` milliseconds, the runner will automatically resume the step
  identified by `step_ref` with a `:timeout` event. This is useful for
  implementing step-level timeouts and retry delays.

  ## Arguments

    * `instance_id` — the identifier of the target instance.
    * `step_ref` — the atom reference of the step to resume.
    * `delay_ms` — the delay in milliseconds before the resume is triggered.

  ## Return

    * `{:ok, reference}` — an adapter-specific reference to the scheduled resume
      (e.g., a timer reference or a job identifier).
    * `{:error, reason}` — if the instance was not found or the resume could not
      be scheduled.
  """
  @callback schedule_resume(
              instance_id :: String.t(),
              step_ref :: atom(),
              delay_ms :: pos_integer()
            ) :: {:ok, reference :: term()} | {:error, reason :: term()}
end
