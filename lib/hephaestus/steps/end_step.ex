defmodule Hephaestus.Steps.End do
  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:ok, String.t()}
  def execute(%Instance{}, _config, %Context{}) do
    {:ok, "completed"}
  end
end
