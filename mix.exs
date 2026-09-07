defmodule Gaiia.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/gmcintire/gaiia"

  def project do
    [
      app: :gaiia,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Elixir client for the Gaiia GraphQL API, with functions generated from the schema.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        flags: [:error_handling, :underspecs, :unmatched_returns]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Core: [Gaiia, Gaiia.Client, Gaiia.Response, Gaiia.Error, Gaiia.RateLimit],
        "Generated API": [Gaiia.Queries, Gaiia.Mutations],
        Helpers: [Gaiia.Files, Gaiia.GlobalID, Gaiia.Pagination, Gaiia.Webhook],
        Internals: [Gaiia.Operation, Gaiia.Schema, Gaiia.TypeRef]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:styler, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
