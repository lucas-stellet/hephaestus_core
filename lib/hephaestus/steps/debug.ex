defmodule Hephaestus.Steps.Debug do
  @moduledoc """
  Built-in step that logs the current context and execution history.

  Outputs `context.initial`, `context.steps`, and `instance.execution_history`
  via `Logger.debug/1`. Returns `{:ok, :completed}`.

  Insert at any point in a workflow to inspect accumulated state during
  development.
  """

  @behaviour Hephaestus.Steps.Step

  require Logger

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec events() :: [:completed]
  def events, do: [:completed]

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:ok, :completed}
  def execute(%Instance{} = instance, _config, %Context{} = context) do
    Logger.debug(fn ->
      [
        "Debug step initial=",
        inspect(context.initial),
        " steps=",
        inspect(context.steps),
        " execution_history=",
        inspect(instance.execution_history)
      ]
    end)

    {:ok, :completed}
  end
end
