defmodule Hephaestus.Steps.WaitForEvent do
  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:async}
  def execute(%Instance{}, _config, %Context{}) do
    {:async}
  end
end
