defmodule Hephaestus.Core.Context do
  @enforce_keys [:initial]
  defstruct initial: %{}, steps: %{}

  @type t :: %__MODULE__{
          initial: map(),
          steps: map()
        }

  @spec new(map()) :: t()
  def new(initial_data), do: %__MODULE__{initial: initial_data, steps: %{}}

  @spec put_step_result(t(), atom(), map()) :: t()
  def put_step_result(%__MODULE__{} = context, step_ref, result) do
    %{context | steps: Map.put(context.steps, step_ref, result)}
  end
end
