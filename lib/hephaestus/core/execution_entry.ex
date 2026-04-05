defmodule Hephaestus.Core.ExecutionEntry do
  @moduledoc """
  A record of a step execution in the workflow history.

  Entries are appended to `Instance.execution_history` as steps complete,
  forming an audit trail of the workflow execution.
  """
  @enforce_keys [:step_ref, :event, :timestamp]
  defstruct [:step_ref, :event, :timestamp, :context_updates]

  @type t :: %__MODULE__{
          step_ref: atom(),
          event: String.t(),
          timestamp: DateTime.t(),
          context_updates: map() | nil
        }
end
