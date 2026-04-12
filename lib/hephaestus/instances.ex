defmodule Hephaestus.Instances do
  @moduledoc false

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
      [] -> raise "No Hephaestus instance running. Start one in your supervision tree."
      [hephaestus_module] -> hephaestus_module
      modules ->
        raise "Multiple Hephaestus instances: #{inspect(modules)}. " <>
                "Pass hephaestus: MyApp.Hephaestus in your workflow's use options."
    end
  end
end
