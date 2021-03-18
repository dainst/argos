defmodule ArgosAPI.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos_api,
      version: "0.1.0",
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
      extra_applications: [
        :logger
      ],
      mod: {ArgosAPI.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:poison, "~> 4.0"},
      {:httpoison, "~> 1.6.2"},
      {:remix, "~> 0.0.1", only: :dev},
      {:plug_cowboy, "~> 2.4"}
      # {:sibling_app_in_umbrella, in_umbrella: true}
    ]
  end
end
