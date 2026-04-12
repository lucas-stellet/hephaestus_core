defmodule Hephaestus.Application do
  @moduledoc """
  OTP Application for Hephaestus.

  Starts the global `Hephaestus.Instances` registry used for
  auto-discovery of Hephaestus runtime modules.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Hephaestus.Instances
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hephaestus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
