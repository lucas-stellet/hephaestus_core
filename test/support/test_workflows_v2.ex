defmodule Hephaestus.Test.V2.LinearWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.ConfigStartWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: {Hephaestus.Test.V2.ConfigStep, %{timeout: 5000}}

  @impl true
  def transit(Hephaestus.Test.V2.ConfigStep, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.V2.FanOutWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done),
    do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]

  def transit(Hephaestus.Test.V2.ParallelA, :done), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.ParallelB, :done), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.JoinStep, :done), do: Hephaestus.Steps.End
end
