defmodule Hephaestus.Core.Instance do
  @moduledoc """
  A runtime instance of a workflow execution.

  Tracks the current state of a workflow as it progresses through steps,
  including which steps are active (being executed), completed, and the
  accumulated context.

  ## Fields

    * `id` - unique identifier supplied by the caller
    * `workflow` - the workflow module being executed
    * `workflow_version` - the version of the workflow definition (positive integer, default 1)
    * `current_step` - the step module currently being processed (or `nil`)
    * `status` - one of `:pending`, `:running`, `:waiting`, `:completed`, `:failed`
    * `context` - `Hephaestus.Core.Context` with initial data and step results
    * `step_configs` - per-step config overrides keyed by step module
    * `active_steps` - `MapSet` of step modules currently being executed
    * `completed_steps` - `MapSet` of step modules that have finished
    * `runtime_metadata` - dynamic metadata accumulated from step executions
    * `telemetry_metadata` - caller metadata merged into emitted telemetry events
    * `telemetry_start_time` - monotonic start time used to compute telemetry durations
    * `execution_history` - list of `Hephaestus.Core.ExecutionEntry` records
  """

  alias Hephaestus.Core.Context

  @enforce_keys [:id, :workflow]
  defstruct [
    :id,
    :workflow,
    :current_step,
    workflow_version: 1,
    status: :pending,
    context: %Context{initial: %{}, steps: %{}},
    step_configs: %{},
    active_steps: MapSet.new(),
    completed_steps: MapSet.new(),
    runtime_metadata: %{},
    execution_history: [],
    telemetry_metadata: %{},
    telemetry_start_time: nil
  ]

  @typedoc "The lifecycle status of a workflow instance."
  @type status :: :pending | :running | :waiting | :completed | :failed

  @typedoc "A workflow instance struct tracking execution state, active/completed steps, and context."
  @type t :: %__MODULE__{
          id: String.t(),
          workflow: module(),
          workflow_version: pos_integer(),
          current_step: module() | nil,
          status: status(),
          context: Context.t(),
          step_configs: %{optional(module()) => map()},
          active_steps: MapSet.t(module()),
          completed_steps: MapSet.t(module()),
          runtime_metadata: map(),
          execution_history: list(),
          telemetry_metadata: map(),
          telemetry_start_time: integer() | nil
        }

  @doc """
  Creates a new workflow instance for the given workflow module and explicit ID.

  ## Parameters

    * `workflow` - the workflow module to execute
    * `version` - the workflow version (positive integer)
    * `context` - a map of initial data passed to the workflow
    * `id` - explicit identifier for the workflow instance

  ## Examples

      iex> instance = Instance.new(MyApp.Workflows.OrderFlow, 1, %{order_id: 123}, "orderid::123")
      iex> instance.status
      :pending
      iex> instance.context.initial
      %{order_id: 123}
      iex> instance.workflow_version
      1

  """
  @spec new(module(), pos_integer(), map(), String.t()) :: t()
  def new(workflow, version, context, id)
      when is_atom(workflow) and is_integer(version) and version > 0 and is_map(context) and
             is_binary(id) do
    %__MODULE__{
      id: id,
      workflow: workflow,
      workflow_version: version,
      context: Context.new(context)
    }
  end
end
