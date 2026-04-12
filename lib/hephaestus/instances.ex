defmodule Hephaestus.Instances do
  @moduledoc """
  Auto-discovery registry for Hephaestus runtime instances.

  Allows workflow facade functions to find the Hephaestus module without
  explicit configuration. Uses Elixir's `Registry` for process-based
  registration with automatic cleanup on termination.

  ## Usage

  The registry is started automatically by `Hephaestus.Application`.
  Each `use Hephaestus` module registers itself via
  `Hephaestus.Instances.Tracker` on boot.

  Workflow facades call `lookup!/0` to discover the registered module:

      Hephaestus.Instances.lookup!()
      #=> MyApp.Hephaestus

  When multiple instances are registered, `lookup!/0` raises with
  instructions to pass `hephaestus: MyApp.Hephaestus` in the workflow's
  `use` options.
  """

  @registry __MODULE__.Registry

  def child_spec(_arg) do
    [keys: :unique, name: @registry]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: @registry)
  end

  def register(hephaestus_module) do
    Registry.register(@registry, hephaestus_module, :ok)
  end

  def lookup! do
    case Registry.select(@registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [] ->
        raise "No Hephaestus instance running. Start one in your supervision tree."

      [hephaestus_module] ->
        hephaestus_module

      modules ->
        raise "Multiple Hephaestus instances: #{inspect(modules)}. " <>
                "Pass hephaestus: MyApp.Hephaestus in your workflow's use options."
    end
  end
end
