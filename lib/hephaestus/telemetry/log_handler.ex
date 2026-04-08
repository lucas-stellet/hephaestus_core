defmodule Hephaestus.Telemetry.LogHandler do
  @moduledoc """
  A structured Logger handler that attaches to Hephaestus telemetry events
  and produces human-readable, grep-friendly log output.

  Opt-in via `attach/1`:

      Hephaestus.Telemetry.LogHandler.attach()

  ## Options

    * `:level` — map of event name to log level override, e.g.
      `%{[:hephaestus, :step, :stop] => :debug}`

    * `:events` — list of event names to handle (default: all from
      `Hephaestus.Telemetry.events/0`)
  """

  require Logger

  alias Hephaestus.Telemetry

  @handler_id "hephaestus-default-log-handler"

  @default_levels %{
    [:hephaestus, :workflow, :start] => :info,
    [:hephaestus, :workflow, :stop] => :info,
    [:hephaestus, :workflow, :exception] => :error,
    [:hephaestus, :workflow, :transition] => :debug,
    [:hephaestus, :step, :start] => :info,
    [:hephaestus, :step, :stop] => :info,
    [:hephaestus, :step, :exception] => :error,
    [:hephaestus, :step, :async] => :warning,
    [:hephaestus, :step, :resume] => :info,
    [:hephaestus, :engine, :advance] => :debug,
    [:hephaestus, :runner, :init] => :info
  }

  @doc """
  Attaches the log handler to Hephaestus telemetry events.

  Returns `:ok` on success, or `{:error, :already_exists}` if already attached.

  ## Options

    * `:level` — map of event name to log level override
    * `:events` — list of event names to subscribe to (default: all)
  """
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    events = Keyword.get(opts, :events, Telemetry.events())
    level_overrides = Keyword.get(opts, :level, %{})
    config = %{level_overrides: level_overrides}

    case :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, config) do
      :ok -> :ok
      {:error, :already_exists} -> {:error, :already_exists}
    end
  end

  @doc """
  Detaches the log handler from Hephaestus telemetry events.

  Returns `:ok` on success, or `{:error, :not_found}` if not currently attached.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    case :telemetry.detach(@handler_id) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc false
  def handle_event(event, measurements, metadata, config) do
    level = resolve_level(event, config.level_overrides)
    duration_ms = convert_duration(measurements[:duration])
    log_metadata = build_metadata(metadata, duration_ms)

    message = format_message(event, measurements, metadata, duration_ms)
    prefixed = prefix_message(metadata, message)

    Logger.log(level, prefixed, log_metadata)
  end

  defp resolve_level(event, level_overrides) do
    Map.get(level_overrides, event) || Map.fetch!(@default_levels, event)
  end

  defp convert_duration(nil), do: nil

  defp convert_duration(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp build_metadata(metadata, duration_ms) do
    base =
      [
        instance_id: metadata[:instance_id],
        workflow: safe_inspect(metadata[:workflow]),
        step: safe_inspect(metadata[:step]),
        event: metadata[:event]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    if duration_ms do
      Keyword.put(base, :duration_ms, duration_ms)
    else
      base
    end
  end

  defp safe_inspect(nil), do: nil
  defp safe_inspect(value), do: inspect(value)

  defp prefix_message(%{instance_id: instance_id}, message) when is_binary(instance_id) do
    "[#{instance_id}] #{message}"
  end

  defp prefix_message(_metadata, message), do: message

  # -- Message formatting per event --

  defp format_message([:hephaestus, :workflow, :start], _measurements, _metadata, _duration_ms) do
    "Workflow started"
  end

  defp format_message([:hephaestus, :workflow, :stop], _measurements, _metadata, duration_ms) do
    "Workflow completed in #{duration_ms}ms"
  end

  defp format_message([:hephaestus, :workflow, :exception], _measurements, metadata, _duration_ms) do
    step = safe_inspect(metadata[:failed_step] || metadata[:step])
    reason = inspect(metadata[:reason])
    "Workflow failed at #{step}: #{reason}"
  end

  defp format_message(
         [:hephaestus, :workflow, :transition],
         _measurements,
         metadata,
         _duration_ms
       ) do
    from_step = safe_inspect(metadata[:from_step])
    targets = metadata[:targets] |> Enum.map(&inspect/1) |> Enum.join(", ")
    "Transition: #{from_step} → #{targets}"
  end

  defp format_message([:hephaestus, :step, :start], _measurements, metadata, _duration_ms) do
    step = safe_inspect(metadata[:step])
    "Step #{step} started"
  end

  defp format_message([:hephaestus, :step, :stop], _measurements, metadata, duration_ms) do
    step = safe_inspect(metadata[:step])
    event = metadata[:event]
    "Step #{step} completed in #{duration_ms}ms → #{event}"
  end

  defp format_message([:hephaestus, :step, :exception], _measurements, metadata, _duration_ms) do
    step = safe_inspect(metadata[:step])
    reason = inspect(metadata[:reason])
    "Step #{step} failed: #{reason}"
  end

  defp format_message([:hephaestus, :step, :async], _measurements, metadata, _duration_ms) do
    step = safe_inspect(metadata[:step])
    "Step #{step} waiting for async event"
  end

  defp format_message([:hephaestus, :step, :resume], _measurements, metadata, duration_ms) do
    step = safe_inspect(metadata[:step])
    resume_event = metadata[:resume_event]
    wait_ms = duration_ms || convert_duration(metadata[:wait_duration])
    "Step #{step} resumed with #{resume_event} (waited #{wait_ms}ms)"
  end

  defp format_message([:hephaestus, :engine, :advance], _measurements, metadata, duration_ms) do
    iteration = metadata[:iteration]
    "Engine advance ##{iteration} (#{duration_ms}ms)"
  end

  defp format_message([:hephaestus, :runner, :init], _measurements, metadata, _duration_ms) do
    name = inspect(metadata[:name])
    "Hephaestus runner initialized: #{name}"
  end
end
