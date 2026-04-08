defmodule Hephaestus.Test.V2.StepA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.StepB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{processed: true}}
end

defmodule Hephaestus.Test.V2.StepC do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.AsyncWait do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:timeout]

  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

defmodule Hephaestus.Test.V2.WaitForEvent do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:received]

  @impl true
  def execute(instance, config, context) do
    Hephaestus.Steps.WaitForEvent.execute(instance, config, context)
  end
end

defmodule Hephaestus.Test.V2.BranchStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:approved, :rejected]

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:should_approve] || context.initial[:approved] do
      {:ok, :approved}
    else
      {:ok, :rejected}
    end
  end
end

defmodule Hephaestus.Test.V2.ApproveStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.RejectStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.ParallelA do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.ParallelB do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.JoinStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.ConfigStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, config, _context), do: {:ok, :done, %{config_received: config}}
end

defmodule Hephaestus.Test.V2.StepWithExtraEvent do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done, :out_of_stock]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done}
end

defmodule Hephaestus.Test.V2.StepWithCustomKey do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def step_key, do: :custom_key

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, _context), do: {:ok, :done, %{data: true}}
end

defmodule Hephaestus.Test.V2.StepWithMetadata do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def events, do: [:done]

  @impl true
  def execute(_instance, _config, context) do
    {:ok, :done, %{processed: true}, %{"order_id" => context.initial[:order_id]}}
  end
end

defmodule Hephaestus.Test.V2.NotAStep do
end
