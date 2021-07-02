defmodule ArgosAggregation.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos_aggregation,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: compiler_paths(Mix.env()),
      deps: deps()
    ]
  end

  def compiler_paths(:test), do: ["lib", "test/helpers"]
  def compiler_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ArgosAggregation.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:poison, "~> 4.0"},
      {:httpoison, "~> 1.8"},
      {:tzdata, "~> 1.0.4"},
      {:geo, "~> 3.3.7"},
      {:sweet_xml, "~> 0.6.6"},
      {:tongue, "~> 2.2"},
      {:ecto, "~> 3.6"}
    ]
  end

end
