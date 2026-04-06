defmodule Hephaestus.Steps.Wait do
  @moduledoc """
  Built-in step that pauses a workflow for a specified duration.

  Returns `{:async}` immediately. The runner is responsible for scheduling
  a resume after the configured delay using `delay_ms/1`.

  ## Config

    * `:duration` - integer amount of time
    * `:unit` - one of `:second`, `:minute`, `:hour`, `:day`
  """

  @behaviour Hephaestus.Steps.Step

  alias Hephaestus.Core.{Context, Instance}

  @impl true
  @spec events() :: [:timeout]
  def events, do: [:timeout]

  @impl true
  @spec execute(Instance.t(), map() | nil, Context.t()) :: {:async}
  def execute(%Instance{}, _config, %Context{}) do
    {:async}
  end

  @spec delay_ms(%{duration: integer(), unit: :second | :minute | :hour | :day}) :: integer()
  def delay_ms(%{duration: duration, unit: :second}), do: duration * 1_000
  def delay_ms(%{duration: duration, unit: :minute}), do: duration * 60_000
  def delay_ms(%{duration: duration, unit: :hour}), do: duration * 3_600_000
  def delay_ms(%{duration: duration, unit: :day}), do: duration * 86_400_000
end
