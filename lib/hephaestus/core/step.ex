defmodule Hephaestus.Core.Step do
  @moduledoc """
  Generic step definition struct.

  Used in workflow definitions to declare a step with its module, optional
  config, and transitions. Implements the `Hephaestus.StepDefinition` protocol.

  ## Example

      %Step{
        ref: :validate,
        module: MyApp.Steps.ValidateOrder,
        transitions: %{"valid" => :process, "invalid" => :reject}
      }

  Steps with config (for reusable step modules):

      %Step{
        ref: :notify,
        module: MyApp.Steps.SendNotification,
        config: %MyApp.NotifyConfig{channel: :email},
        transitions: %{"sent" => :done}
      }

  Fan-out transitions (parallel execution):

      %Step{
        ref: :start,
        module: MyApp.Steps.Begin,
        transitions: %{"ready" => [:check_stock, :check_fraud]}
      }
  """

  @enforce_keys [:ref, :module]
  defstruct [:ref, :module, :config, :transitions]

  @type t :: %__MODULE__{
          ref: atom(),
          module: module(),
          config: any(),
          transitions: map() | nil
        }
end

defimpl Hephaestus.StepDefinition, for: Hephaestus.Core.Step do
  def ref(step), do: step.ref
  def module(step), do: step.module
  def config(step), do: step.config
  def transitions(step), do: step.transitions
end
