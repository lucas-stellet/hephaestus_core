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

  @doc """
  Creates a new workflow context with the given initial data.

  The `initial_data` map is stored under the `:initial` key and remains
  immutable throughout the workflow execution. The `:steps` map starts empty
  and is populated as steps complete.

  ## Parameters

    * `initial_data` - a map of data available to all steps in the workflow

  ## Returns

  A `t:t/0` struct.

  ## Example

      iex> Context.new(%{order_id: 123})
      %Context{initial: %{order_id: 123}, steps: %{}}
  """
  @spec new(map()) :: t()
  def new(initial_data), do: %__MODULE__{initial: initial_data, steps: %{}}

  @doc """
  Stores a step's result in the context under the given reference.

  The result is placed in the `:steps` map keyed by `step_ref`, making it
  accessible to subsequent steps as `context.steps.<step_ref>`.

  ## Parameters

    * `context` - the current `t:t/0` struct
    * `step_ref` - an atom identifying the step (matches the ref in the workflow graph)
    * `result` - a map containing the step's output data

  ## Returns

  An updated `t:t/0` struct with the new step result merged into `:steps`.

  ## Example

      iex> context = Context.new(%{order_id: 123})
      iex> Context.put_step_result(context, :validate, %{valid: true})
      %Context{initial: %{order_id: 123}, steps: %{validate: %{valid: true}}}
  """
  @spec put_step_result(t(), atom(), map()) :: t()
  def put_step_result(%__MODULE__{} = context, step_ref, result) do
    %{context | steps: Map.put(context.steps, step_ref, result)}
  end
end
