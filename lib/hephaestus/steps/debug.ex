defmodule Hephaestus.Steps.Debug do
  @behaviour Hephaestus.Steps.Step

  require Logger

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:ok, String.t()}
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

    {:ok, "completed"}
  end
end
