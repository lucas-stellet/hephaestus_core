defmodule Hephaestus.Test.PassStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.PassWithContextStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{processed: true}}
end

defmodule Hephaestus.Test.BranchStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:approved, :rejected]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:should_approve] do
      {:ok, :approved}
    else
      {:ok, :rejected}
    end
  end
end

defmodule Hephaestus.Test.AsyncStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:timeout]

  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

defmodule Hephaestus.Test.WaitForEventStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:payment_confirmed]

  @impl true
  def execute(instance, config, context) do
    Hephaestus.Steps.WaitForEvent.execute(instance, config, context)
  end
end

defmodule Hephaestus.Test.FailStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:failed]

  @impl true
  def execute(_instance, _config, _context), do: {:error, :something_went_wrong}
end

defmodule Hephaestus.Test.Linear.StepA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Linear.StepB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Branch.Approve do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Branch.Reject do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Parallel.Start do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Parallel.BranchA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Parallel.BranchB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Parallel.BranchC do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Parallel.Join do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.MixedParallel.Start do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.MixedParallel.Sync do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.MixedParallel.Async do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:timeout]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.AsyncStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.MixedParallel.Join do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Async.StepA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Async.Wait do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:timeout]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.AsyncStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Async.StepB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Event.StepA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Event.WaitForEvent do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:payment_confirmed]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.WaitForEventStep.execute(instance, config, context)
end

defmodule Hephaestus.Test.Event.StepB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(instance, config, context), do: Hephaestus.Test.PassWithContextStep.execute(instance, config, context)
end
