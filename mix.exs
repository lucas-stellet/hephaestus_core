defmodule Hephaestus.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hephaestus-org/hephaestus_core"

  def project do
    [
      app: :hephaestus,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      description: "A lightweight, extensible workflow engine for Elixir/OTP applications.",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Hephaestus.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "Hephaestus",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libgraph, "~> 0.16"},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end
end
