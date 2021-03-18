defmodule ArgosData.MixProject do
  use Mix.Project

  def project do
    [
      app: :argos_data,
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
      extra_applications: [:logger],
      mod: {ArgosData.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tzdata, "~> 1.0.4"},
      {:geo, "~> 3.3.7"},
      {:sweet_xml, "~> 0.6.6"}
      # {:sibling_app_in_umbrella, in_umbrella: true}
    ]
  end

end
