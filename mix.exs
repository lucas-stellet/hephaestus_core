defmodule Hephaestus.MixProject do
  use Mix.Project

  @version "0.1.3"
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
      source_url: @source_url,
      extras: [
        "guides/getting-started.md",
        "guides/architecture.md",
        "guides/extensions.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          Hephaestus,
          Hephaestus.Core.Engine,
          Hephaestus.Core.Instance,
          Hephaestus.Core.Context,
          Hephaestus.Core.Workflow,
          Hephaestus.Workflow,
          Hephaestus.Core.ExecutionEntry
        ],
        Steps: [
          Hephaestus.Steps.Step,
          Hephaestus.Steps.Done,
          Hephaestus.Steps.Wait,
          Hephaestus.Steps.WaitForEvent,
          Hephaestus.Steps.Debug
        ],
        Runtime: [
          Hephaestus.Runtime.Runner,
          Hephaestus.Runtime.Runner.Local,
          Hephaestus.Runtime.Storage,
          Hephaestus.Runtime.Storage.ETS
        ],
        Connectors: [
          Hephaestus.Connectors.Connector
        ]
      ]
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
