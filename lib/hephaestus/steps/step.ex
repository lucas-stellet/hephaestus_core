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

  @typedoc "Optional configuration map passed to a step's `execute/3` callback, or `nil` if no config is set."
  @type config :: map() | nil
  @typedoc "An atom representing the outcome of a step execution, used to determine the next transition in the workflow."
  @type event :: atom()
  @typedoc "A map of key-value pairs to merge into the workflow context after a step completes."
  @type context_updates :: map()
  @typedoc "Retry configuration controlling how the runner retries a failed step."
  @type retry_config :: %{
          max_attempts: pos_integer(),
          backoff: :exponential | :linear | :constant,
          max_backoff: pos_integer()
        }
  @typedoc """
  The return type of `execute/3`.

  * `{:ok, event}` — step completed synchronously, emitting the named event.
  * `{:ok, event, context_updates}` — completed with additional data to store in the workflow context.
  * `{:async}` — step is asynchronous and will be resumed later (e.g., after a timer or external event).
  * `{:error, reason}` — step failed with the given reason.
  """
  @type result ::
          {:ok, event()}
          | {:ok, event(), context_updates()}
          | {:async}
          | {:error, term()}

  @doc """
  Returns the list of events this step can emit.

  The workflow engine uses this list to validate that transitions defined in the
  workflow graph match the events the step actually produces. Each event atom
  should correspond to a possible outcome of `execute/3`.

  ## Examples

      @impl true
      def events, do: [:done]

  A step with multiple outcomes:

      @impl true
      def events, do: [:approved, :rejected]
  """
  @callback events() :: [event()]

  @doc """
  Returns a custom atom key identifying this step.

  Optional. When not implemented, the workflow engine derives the key from the
  module name. Override this to provide a shorter or more meaningful identifier
  for storage and logging.

  ## Examples

      @impl true
      def step_key, do: :validate
  """
  @callback step_key() :: atom()

  @doc """
  Returns the retry configuration for this step.

  Optional. When implemented, the runner will automatically retry the step on
  failure according to the returned configuration, which specifies the maximum
  number of attempts, backoff strategy (`:exponential`, `:linear`, or
  `:constant`), and maximum backoff interval in milliseconds.

  ## Examples

      @impl true
      def retry_config do
        %{max_attempts: 3, backoff: :exponential, max_backoff: 30_000}
      end
  """
  @callback retry_config() :: retry_config()

  @doc """
  Executes the step logic.

  Receives the current workflow `instance`, an optional `config` map defined in
  the workflow graph for this step, and the execution `context` containing
  initial data and results from previous steps.

  Must return a `t:result/0` tuple indicating the outcome.

  ## Examples

  Synchronous step returning an event:

      @impl true
      def execute(_instance, _config, _context), do: {:ok, :done}

  Step that reads context and returns updates:

      @impl true
      def execute(_instance, _config, context) do
        items = context.initial.items
        {:ok, :done, %{item_count: length(items)}}
      end

  Asynchronous step (waits for external resume):

      @impl true
      def execute(_instance, _config, _context), do: {:async}
  """
  @callback execute(instance :: Instance.t(), config :: config(), context :: Context.t()) ::
              result()

  @optional_callbacks [step_key: 0, retry_config: 0]
end
