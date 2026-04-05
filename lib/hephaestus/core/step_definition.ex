defprotocol Hephaestus.StepDefinition do
  @moduledoc """
  Protocol for step definitions in workflow graphs.

  Any struct implementing this protocol can be used as a step in a workflow.
  The engine interacts with steps exclusively through this protocol, enabling
  extensibility via custom step types (e.g., channel steps, connector steps).

  `Hephaestus.Core.Step` provides the default implementation. External libraries
  can define their own structs with domain-specific fields and implement this
  protocol to be recognized by the engine.
  """
  def ref(step)
  def module(step)
  def config(step)
  def transitions(step)
end
