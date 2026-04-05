defprotocol Hephaestus.StepDefinition do
  def ref(step)
  def module(step)
  def config(step)
  def transitions(step)
end
