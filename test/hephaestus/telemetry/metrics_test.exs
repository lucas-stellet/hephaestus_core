defmodule Hephaestus.Telemetry.MetricsTest do
  use ExUnit.Case, async: true

  alias Hephaestus.Telemetry.Metrics

  # Telemetry.Metrics stores .name as an atom list (e.g. [:hephaestus, :workflow, :start, :count]).
  # This helper converts it to the dotted string form for readable assertions.
  defp metric_name(metric), do: metric.name |> Enum.map_join(".", &Atom.to_string/1)

  describe "metrics/0" do
    test "returns all 9 metric definitions" do
      # Act
      metrics = Metrics.metrics()

      # Assert
      assert length(metrics) == 9
    end

    test "includes workflow counters and distributions" do
      # Act
      metrics = Metrics.metrics()
      names = Enum.map(metrics, &metric_name/1)

      # Assert
      assert "hephaestus.workflow.start.count" in names
      assert "hephaestus.workflow.stop.count" in names
      assert "hephaestus.workflow.exception.count" in names
      assert "hephaestus.workflow.stop.duration" in names
    end

    test "includes step counters and distributions" do
      # Act
      metrics = Metrics.metrics()
      names = Enum.map(metrics, &metric_name/1)

      # Assert
      assert "hephaestus.step.stop.duration" in names
      assert "hephaestus.step.exception.count" in names
      assert "hephaestus.step.async.count" in names
      assert "hephaestus.step.resume.wait_duration" in names
    end

    test "includes engine last_value gauge" do
      # Act
      metrics = Metrics.metrics()
      names = Enum.map(metrics, &metric_name/1)

      # Assert
      assert "hephaestus.engine.advance.active_steps_count" in names
    end

    test "all metrics have correct types" do
      # Act
      metrics = Metrics.metrics()

      # Assert
      counters = Enum.filter(metrics, &match?(%Telemetry.Metrics.Counter{}, &1))
      distributions = Enum.filter(metrics, &match?(%Telemetry.Metrics.Distribution{}, &1))
      last_values = Enum.filter(metrics, &match?(%Telemetry.Metrics.LastValue{}, &1))

      assert length(counters) == 5
      assert length(distributions) == 3
      assert length(last_values) == 1
    end
  end

  describe "metrics/1 with scope" do
    test "scope: :workflow returns only workflow metrics" do
      # Act
      metrics = Metrics.metrics(scope: :workflow)

      # Assert
      assert length(metrics) == 4

      assert Enum.all?(metrics, fn m ->
               String.starts_with?(metric_name(m), "hephaestus.workflow")
             end)
    end

    test "scope: :step returns only step metrics" do
      # Act
      metrics = Metrics.metrics(scope: :step)

      # Assert
      assert length(metrics) == 4

      assert Enum.all?(metrics, fn m ->
               String.starts_with?(metric_name(m), "hephaestus.step")
             end)
    end

    test "scope: :engine returns only engine metrics" do
      # Act
      metrics = Metrics.metrics(scope: :engine)

      # Assert
      assert length(metrics) == 1
      assert metric_name(hd(metrics)) == "hephaestus.engine.advance.active_steps_count"
    end
  end

  describe "metric tags" do
    test "workflow duration tagged by workflow" do
      # Act
      metrics = Metrics.metrics(scope: :workflow)
      duration = Enum.find(metrics, &(metric_name(&1) == "hephaestus.workflow.stop.duration"))

      # Assert
      assert :workflow in duration.tags
    end

    test "step duration tagged by workflow and step" do
      # Act
      metrics = Metrics.metrics(scope: :step)
      duration = Enum.find(metrics, &(metric_name(&1) == "hephaestus.step.stop.duration"))

      # Assert
      assert :workflow in duration.tags
      assert :step in duration.tags
    end

    test "step exception tagged by kind" do
      # Act
      metrics = Metrics.metrics(scope: :step)
      exception = Enum.find(metrics, &(metric_name(&1) == "hephaestus.step.exception.count"))

      # Assert
      assert :kind in exception.tags
    end
  end
end
