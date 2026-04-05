defmodule Hephaestus.Core.Context do
  @moduledoc """
  Workflow execution context carrying initial data and step results.

  The context has two namespaced sections:

    * `initial` - immutable data provided when starting the workflow instance
    * `steps` - results accumulated from completed steps, keyed by step ref

  Step results are always namespaced to avoid conflicts in fan-in scenarios
  where parallel steps complete simultaneously.

  ## Example

      context = Context.new(%{order_id: 123})
      context = Context.put_step_result(context, :validate, %{valid: true})

      context.initial.order_id     #=> 123
      context.steps.validate.valid #=> true
  """

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
