defmodule Hephaestus.Core.Step do
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
