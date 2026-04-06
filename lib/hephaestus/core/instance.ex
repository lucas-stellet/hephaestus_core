defmodule Hephaestus.Core.Instance do
  @moduledoc """
  A runtime instance of a workflow execution.

  Tracks the current state of a workflow as it progresses through steps,
  including which steps are active (being executed), completed, and the
  accumulated context.

  ## Fields

    * `id` - unique identifier (UUID v4)
    * `workflow` - the workflow module being executed
    * `current_step` - the step module currently being processed (or `nil`)
    * `status` - one of `:pending`, `:running`, `:waiting`, `:completed`, `:failed`
    * `context` - `Hephaestus.Core.Context` with initial data and step results
    * `step_configs` - per-step config overrides keyed by step module
    * `active_steps` - `MapSet` of step modules currently being executed
    * `completed_steps` - `MapSet` of step modules that have finished
    * `execution_history` - list of `Hephaestus.Core.ExecutionEntry` records
  """

  alias Hephaestus.Core.Context

  @enforce_keys [:id, :workflow]
  defstruct [
    :id,
    :workflow,
    :current_step,
    status: :pending,
    context: %Context{initial: %{}, steps: %{}},
    step_configs: %{},
    active_steps: MapSet.new(),
    completed_steps: MapSet.new(),
    execution_history: []
  ]

  @type status :: :pending | :running | :waiting | :completed | :failed

  @type t :: %__MODULE__{
          id: String.t(),
          workflow: module(),
          current_step: module() | nil,
          status: status(),
          context: Context.t(),
          step_configs: %{optional(module()) => map()},
          active_steps: MapSet.t(module()),
          completed_steps: MapSet.t(module()),
          execution_history: list()
        }

  @spec new(module(), map()) :: t()
  def new(workflow, context \\ %{}) when is_atom(workflow) and is_map(context) do
    %__MODULE__{
      id: generate_uuid(),
      workflow: workflow,
      context: Context.new(context)
    }
  end

  defp generate_uuid do
    <<a1::32, a2::16, a3::16, a4::16, a5::48>> = :crypto.strong_rand_bytes(16)
    version = bor(band(a3, 0x0FFF), 0x4000)
    variant = bor(band(a4, 0x3FFF), 0x8000)

    [
      encode(a1, 8),
      encode(a2, 4),
      encode(version, 4),
      encode(variant, 4),
      encode(a5, 12)
    ]
    |> Enum.join("-")
  end

  defp encode(value, width) do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(width, "0")
  end

  defp band(left, right), do: Bitwise.band(left, right)
  defp bor(left, right), do: Bitwise.bor(left, right)
end
