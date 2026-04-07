defmodule Hephaestus.Connectors.Connector do
  @moduledoc """
  Contract for external service connectors.
  """

  @typedoc """
  An atom identifying the operation to perform on the external service.

  Each connector defines its own set of supported actions (e.g., `:get_task`, `:create_task`).
  """
  @type action :: atom()

  @typedoc """
  A map of input parameters for the action being executed.

  The expected keys depend on the specific action (e.g., `%{task_id: "123"}` for a `:get_task` action).
  """
  @type params :: map()

  @typedoc """
  A map of configuration values required by the connector.

  Typically holds credentials and connection settings (e.g., `%{api_key: "secret"}`).
  """
  @type config :: map()

  @typedoc """
  A map containing the data returned by a successful action execution.
  """
  @type result :: map()

  @typedoc """
  The reason for a failed action execution.

  Can be any term, though atoms like `:unsupported_action` or descriptive strings are recommended.
  """
  @type error_reason :: term()

  @doc """
  Executes the given `action` against the external service.

  Receives the action to perform, a map of `params` specific to that action,
  and a `config` map with credentials or connection settings.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  @callback execute(action(), params(), config()) ::
              {:ok, result()} | {:error, error_reason()}

  @doc """
  Returns the list of actions supported by this connector.
  """
  @callback supported_actions() :: [action()]
end
