defmodule Hephaestus.Telemetry.Metrics do
  @moduledoc """
  Pre-built `Telemetry.Metrics` definitions for Hephaestus workflow events.

  Returns metric definitions compatible with any reporter (Prometheus, StatsD,
  LiveDashboard, etc.). Use `metrics/1` with a `:scope` option to filter by
  `:workflow`, `:step`, or `:engine`.

  ## Usage

      # All metrics
      Hephaestus.Telemetry.Metrics.metrics()

      # Only workflow metrics
      Hephaestus.Telemetry.Metrics.metrics(scope: :workflow)

  ## Integration with LiveDashboard

      live_dashboard "/dashboard",
        metrics: {Hephaestus.Telemetry.Metrics, :metrics}
  """

  import Telemetry.Metrics

  @type scope :: :workflow | :step | :engine

  @doc """
  Returns a list of `Telemetry.Metrics` definitions for Hephaestus events.

  ## Options

    * `:scope` - Filter metrics by scope. One of `:workflow`, `:step`, or `:engine`.
      When omitted, returns all metrics.

  """
  @spec metrics(keyword()) :: [Telemetry.Metrics.t()]
  def metrics(opts \\ []) do
    scope = Keyword.get(opts, :scope)

    all_metrics()
    |> filter_by_scope(scope)
  end

  defp all_metrics do
    workflow_metrics() ++ step_metrics() ++ engine_metrics()
  end

  defp workflow_metrics do
    [
      counter("hephaestus.workflow.start.count",
        event_name: [:hephaestus, :workflow, :start],
        measurement: :system_time,
        tags: [:workflow]
      ),
      counter("hephaestus.workflow.stop.count",
        event_name: [:hephaestus, :workflow, :stop],
        measurement: :duration,
        tags: [:workflow]
      ),
      counter("hephaestus.workflow.exception.count",
        event_name: [:hephaestus, :workflow, :exception],
        tags: [:workflow, :failed_step]
      ),
      distribution("hephaestus.workflow.stop.duration",
        event_name: [:hephaestus, :workflow, :stop],
        measurement: :duration,
        tags: [:workflow],
        unit: {:native, :millisecond}
      )
    ]
  end

  defp step_metrics do
    [
      distribution("hephaestus.step.stop.duration",
        event_name: [:hephaestus, :step, :stop],
        measurement: :duration,
        tags: [:workflow, :step],
        unit: {:native, :millisecond}
      ),
      counter("hephaestus.step.exception.count",
        event_name: [:hephaestus, :step, :exception],
        tags: [:workflow, :step, :kind]
      ),
      counter("hephaestus.step.async.count",
        event_name: [:hephaestus, :step, :async],
        tags: [:workflow, :step]
      ),
      distribution("hephaestus.step.resume.wait_duration",
        event_name: [:hephaestus, :step, :resume],
        measurement: :wait_duration,
        tags: [:workflow, :step, :source],
        unit: {:native, :millisecond}
      )
    ]
  end

  defp engine_metrics do
    [
      last_value("hephaestus.engine.advance.active_steps_count",
        event_name: [:hephaestus, :engine, :advance],
        measurement: :active_steps_count,
        tags: [:workflow]
      )
    ]
  end

  defp filter_by_scope(_metrics, :workflow), do: workflow_metrics()
  defp filter_by_scope(_metrics, :step), do: step_metrics()
  defp filter_by_scope(_metrics, :engine), do: engine_metrics()
  defp filter_by_scope(metrics, nil), do: metrics
end
