defmodule Hephaestus.Test.LinearWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.Linear.StepA

  @impl true
  def transit(Hephaestus.Test.Linear.StepA, :done), do: Hephaestus.Test.Linear.StepB
  def transit(Hephaestus.Test.Linear.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.BranchWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.BranchStep

  @impl true
  def transit(Hephaestus.Test.BranchStep, :approved), do: Hephaestus.Test.Branch.Approve
  def transit(Hephaestus.Test.BranchStep, :rejected), do: Hephaestus.Test.Branch.Reject
  def transit(Hephaestus.Test.Branch.Approve, :done), do: Hephaestus.Steps.End
  def transit(Hephaestus.Test.Branch.Reject, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.ParallelWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.Parallel.Start

  @impl true
  def transit(Hephaestus.Test.Parallel.Start, :done),
    do: [Hephaestus.Test.Parallel.BranchA, Hephaestus.Test.Parallel.BranchB, Hephaestus.Test.Parallel.BranchC]

  def transit(Hephaestus.Test.Parallel.BranchA, :done), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.BranchB, :done), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.BranchC, :done), do: Hephaestus.Test.Parallel.Join
  def transit(Hephaestus.Test.Parallel.Join, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.MixedParallelWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.MixedParallel.Start

  @impl true
  def transit(Hephaestus.Test.MixedParallel.Start, :done),
    do: [Hephaestus.Test.MixedParallel.Sync, Hephaestus.Test.MixedParallel.Async]

  def transit(Hephaestus.Test.MixedParallel.Sync, :done), do: Hephaestus.Test.MixedParallel.Join
  def transit(Hephaestus.Test.MixedParallel.Async, :timeout), do: Hephaestus.Test.MixedParallel.Join
  def transit(Hephaestus.Test.MixedParallel.Join, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.AsyncWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.Async.StepA

  @impl true
  def transit(Hephaestus.Test.Async.StepA, :done), do: Hephaestus.Test.Async.Wait
  def transit(Hephaestus.Test.Async.Wait, :timeout), do: Hephaestus.Test.Async.StepB
  def transit(Hephaestus.Test.Async.StepB, :done), do: Hephaestus.Steps.End
end

defmodule Hephaestus.Test.EventWorkflow do
  use Hephaestus.Workflow

  @impl true
  def start, do: Hephaestus.Test.Event.StepA

  @impl true
  def transit(Hephaestus.Test.Event.StepA, :done), do: Hephaestus.Test.Event.WaitForEvent
  def transit(Hephaestus.Test.Event.WaitForEvent, :payment_confirmed), do: Hephaestus.Test.Event.StepB
  def transit(Hephaestus.Test.Event.StepB, :done), do: Hephaestus.Steps.End
end
