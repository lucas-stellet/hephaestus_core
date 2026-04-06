defmodule Hephaestus.Steps.End do
  @moduledoc """
  Built-in terminal step that marks a workflow as complete.

  Always returns `{:ok, :end}`. Every workflow must have at least one
  path leading to an End step.
  """

  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec events() :: [:end]
  def events, do: [:end]

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:ok, :end}
  def execute(%Instance{}, _config, %Context{}) do
    {:ok, :end}
  end
end
