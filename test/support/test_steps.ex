defmodule Hephaestus.Test.PassStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:ok, "done"}
end

defmodule Hephaestus.Test.PassWithContextStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:ok, "done", %{processed: true}}
end

defmodule Hephaestus.Test.BranchStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, context) do
    if context.initial[:should_approve] do
      {:ok, "approved"}
    else
      {:ok, "rejected"}
    end
  end
end

defmodule Hephaestus.Test.AsyncStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:async}
end

defmodule Hephaestus.Test.FailStep do
  @behaviour Hephaestus.Steps.Step

  @impl true
  def execute(_instance, _config, _context), do: {:error, :something_went_wrong}
end
