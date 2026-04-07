defmodule Hephaestus.Steps.Step do
  @moduledoc """
  Behaviour for workflow step implementations.

  Every step in a workflow must implement this behaviour. The `execute/3` callback
  receives the current instance, optional config, and the execution context.

  ## Return values

    * `{:ok, event}` - step completed synchronously, emitting the named event
    * `{:ok, event, context_updates}` - completed with data to store in context
    * `{:async}` - step is async (e.g., waiting for external event or timer)
    * `{:error, reason}` - step failed

  ## Example

      defmodule MyApp.Steps.ValidateOrder do
        @behaviour Hephaestus.Steps.Step

        @impl true
        def events, do: [:valid, :invalid]

        @impl true
        def execute(_instance, _config, context) do
          if context.initial[:items] && length(context.initial.items) > 0 do
            {:ok, :valid, %{item_count: length(context.initial.items)}}
          else
            {:ok, :invalid}
          end
        end
      end
  """

  alias Hephaestus.Core.{Context, Instance}

  @type config :: map() | nil
  @type event :: atom()
  @type context_updates :: map()
  @type retry_config :: %{
          max_attempts: pos_integer(),
          backoff: :exponential | :linear | :constant,
          max_backoff: pos_integer()
        }
  @type result ::
          {:ok, event()}
          | {:ok, event(), context_updates()}
          | {:async}
          | {:error, term()}

  @callback events() :: [event()]
  @callback step_key() :: atom()
  @callback retry_config() :: retry_config()
  @callback execute(instance :: Instance.t(), config :: config(), context :: Context.t()) :: result()

  @optional_callbacks [step_key: 0, retry_config: 0]
end
