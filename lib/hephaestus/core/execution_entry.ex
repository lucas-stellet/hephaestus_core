defmodule Hephaestus.Core.ExecutionEntry do
  @enforce_keys [:step_ref, :event, :timestamp]
  defstruct [:step_ref, :event, :timestamp, :context_updates]

  @type t :: %__MODULE__{
          step_ref: atom(),
          event: String.t(),
          timestamp: DateTime.t(),
          context_updates: map() | nil
        }
end
