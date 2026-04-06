defmodule Hephaestus.Steps.Done do
  @moduledoc """
  Built-in terminal step that marks a workflow as complete.

  Always returns `{:ok, :done}`. Every workflow must have at least one
  path leading to a Done step.
  """

  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec events() :: [:done]
  def events, do: [:done]

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:ok, :done}
  def execute(%Instance{}, _config, %Context{}) do
    {:ok, :done}
  end
end
