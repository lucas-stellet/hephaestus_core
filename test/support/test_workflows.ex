defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.Linear.StepA

  @impl true
  def transit(Hephaestus.Test.Linear.StepA, :done, _ctx), do: Hephaestus.Test.Linear.StepB
  def transit(Hephaestus.Test.Linear.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.BranchWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.BranchStep

  @impl true
  def transit(Hephaestus.Test.BranchStep, :approved, _ctx), do: Hephaestus.Test.Branch.Approve
  def transit(Hephaestus.Test.BranchStep, :rejected, _ctx), do: Hephaestus.Test.Branch.Reject
  def transit(Hephaestus.Test.Branch.Approve, :done, _ctx), do: Hephaestus.Steps.Done
  def transit(Hephaestus.Test.Branch.Reject, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.ParallelWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.Parallel.Start

  @impl true
  def transit(Hephaestus.Test.Parallel.Start, :done, _ctx),
    do: [
      Hephaestus.Test.Parallel.BranchA,
      Hephaestus.Test.Parallel.BranchB,
      Hephaestus.Test.Parallel.BranchC
    ]

  def transit(Hephaestus.Test.Parallel.BranchA, :done, _ctx), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.BranchB, :done, _ctx), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.BranchC, :done, _ctx), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.Join, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.MixedParallelWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.MixedParallel.Start

  @impl true
  def transit(Hephaestus.Test.MixedParallel.Start, :done, _ctx),
    do: [Hephaestus.Test.MixedParallel.Sync, Hephaestus.Test.MixedParallel.Async]

  def transit(Hephaestus.Test.MixedParallel.Sync, :done, _ctx),
    do: Hephaestus.Test.MixedParallel.Join

  def transit(Hephaestus.Test.MixedParallel.Async, :timeout, _ctx),
    do: Hephaestus.Test.MixedParallel.Join

  def transit(Hephaestus.Test.MixedParallel.Join, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.AsyncWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.Async.StepA

  @impl true
  def transit(Hephaestus.Test.Async.StepA, :done, _ctx), do: Hephaestus.Test.Async.Wait
  def transit(Hephaestus.Test.Async.Wait, :timeout, _ctx), do: Hephaestus.Test.Async.StepB
  def transit(Hephaestus.Test.Async.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end

defmodule Hephaestus.Test.EventWorkflow do
  use Hephaestus.Workflow, unique: [key: "test"]

  @impl true
  def start, do: Hephaestus.Test.Event.StepA

  @impl true
  def transit(Hephaestus.Test.Event.StepA, :done, _ctx), do: Hephaestus.Test.Event.WaitForEvent

  def transit(Hephaestus.Test.Event.WaitForEvent, :payment_confirmed, _ctx),
    do: Hephaestus.Test.Event.StepB

  def transit(Hephaestus.Test.Event.StepB, :done, _ctx), do: Hephaestus.Steps.Done
end
