defmodule Argos.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:poison, "~> 4.0"},
      {:httpoison, "~> 1.6.2"},
      {:remix, "~> 0.0.1", only: :dev}
    ]
  end

  defp aliases do
    [
      "update-mapping": [
        "run --eval 'ArgosData.Release.update_mapping()' -- --script"
      ],
      "seed.projects": [
        "run --eval 'ArgosData.ProjectCLI.run()' -- --script"
      ]
    ]
  end
end
