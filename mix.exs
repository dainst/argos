defmodule Argos.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Argos.Application, []},
      extra_applications: [:logger],
      remix: [:remix]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:poison, "~> 3.0"},
      {:httpoison, "~> 1.6.2"},
      {:remix, "~> 0.0.1", only: :dev},
      {:tzdata, "~> 1.0.4"},
      {:geo, "~> 3.3.7"},
      {:sweet_xml, "~> 0.6.6"},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
