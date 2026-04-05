defmodule Hephaestus.Connectors.Connector do
  @moduledoc """
  Contract for external service connectors.
  """

  @type action :: atom()
  @type params :: map()
  @type config :: map()
  @type result :: map()
  @type error_reason :: term()

  @callback execute(action(), params(), config()) ::
              {:ok, result()} | {:error, error_reason()}

  @callback supported_actions() :: [action()]
end
