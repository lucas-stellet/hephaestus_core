defmodule Hephaestus.Instances.Tracker do
  @moduledoc false

  use GenServer

  def start_link(hephaestus_module) do
    GenServer.start(__MODULE__, hephaestus_module)
  end

  def start_supervised_link(hephaestus_module) do
    GenServer.start_link(__MODULE__, hephaestus_module)
  end

  def child_spec(hephaestus_module) do
    %{
      id: {__MODULE__, hephaestus_module},
      start: {__MODULE__, :start_supervised_link, [hephaestus_module]}
    }
  end

  @impl true
  def init(hephaestus_module) do
    Hephaestus.Instances.register(hephaestus_module)
    {:ok, hephaestus_module}
  end
end
