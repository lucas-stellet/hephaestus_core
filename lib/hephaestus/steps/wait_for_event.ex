defmodule Hephaestus.Steps.WaitForEvent do
  @moduledoc """
  Built-in step that pauses a workflow until an external event is received.

  Returns `{:async}` immediately. The workflow remains in `:waiting` status
  until `resume/2` is called with the expected event name.

  ## Config

    * `:event_name` - the event name to wait for (e.g., `"payment_confirmed"`)
    * `:timeout_ms` - optional timeout in milliseconds
  """

  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec events() :: [:received]
  def events, do: [:received]

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:async}
  def execute(%Instance{}, _config, %Context{}) do
    {:async}
  end
end
