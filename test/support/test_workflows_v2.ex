defmodule Hephaestus.Test.V2.LinearWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.ConfigStartWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: {Hephaestus.Test.V2.ConfigStep, %{timeout: 5000}}

  @impl true
  def transit(Hephaestus.Test.V2.ConfigStep, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.BranchWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.BranchStep

  @impl true
  def transit(Hephaestus.Test.V2.BranchStep, :approved, _ctx), do: Hephaestus.Test.V2.ApproveStep
  def transit(Hephaestus.Test.V2.BranchStep, :rejected, _ctx), do: Hephaestus.Test.V2.RejectStep
  def transit(Hephaestus.Test.V2.ApproveStep, :done, _ctx), do: Hephaestus.Steps.Done
  def transit(Hephaestus.Test.V2.RejectStep, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.FanOutWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx),
    do: [Hephaestus.Test.V2.ParallelA, Hephaestus.Test.V2.ParallelB]

  def transit(Hephaestus.Test.V2.ParallelA, :done, _ctx), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.ParallelB, :done, _ctx), do: Hephaestus.Test.V2.JoinStep
  def transit(Hephaestus.Test.V2.JoinStep, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.AsyncWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.AsyncWait
  def transit(Hephaestus.Test.V2.AsyncWait, :timeout, _ctx), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.EventWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.WaitForEvent
  def transit(Hephaestus.Test.V2.WaitForEvent, :received, _ctx), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.TaggedWorkflow do
  use Hephaestus.Workflow,
    tags: ["onboarding", "growth"],
    metadata: %{"team" => "growth", "priority" => "high"}

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  def transit(Hephaestus.Test.V2.StepA, :done, _ctx), do: Hephaestus.Test.V2.StepB
  def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.V2.DynamicWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.V2.StepA

  @impl true
  @targets [Hephaestus.Test.V2.StepB, Hephaestus.Test.V2.StepC]
  def transit(Hephaestus.Test.V2.StepA, :done, ctx) do
    if ctx.initial.use_b do
      Hephaestus.Test.V2.StepB
    else
      Hephaestus.Test.V2.StepC
    end
  end

  def transit(Hephaestus.Test.V2.StepB, :done, _ctx), do: Hephaestus.Steps.Done
  def transit(Hephaestus.Test.V2.StepC, :done, _ctx), do: Hephaestus.Steps.Done
end
