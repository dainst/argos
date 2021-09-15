defmodule ArgosAPI.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos_api,
      version: "0.2.3",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ArgosAPI.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:argos_core, in_umbrella: true},
      {:poison, "~> 4.0", override: true},
      {:finch, "~> 0.7"},
      {:exsync, "~> 0.2", only: :dev},
      {:plug_cowboy, "~> 2.4"},
      {:cors_plug, "~> 2.0"},
      {:open_api_spex, "~> 3.10"}
    ]
  end
end
