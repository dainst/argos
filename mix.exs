defmodule Argos.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        api: [
          applications: [
            argos_api: :permanent
          ]
        ],
        aggregation: [
          applications: [
            argos_aggregation: :permanent
          ]
        ]
      ],
      aliases: aliases()
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end

  defp aliases do
    [
      "update-mapping": [
        "run --eval 'ArgosAPI.Release.update_mapping()' -- --script"
      ],
      "seed.projects": [
        "run --eval 'ArgosAggregation.ProjectCLI.run()' -- --script"
      ],
      "seed.bibliography": [
        "run --eval 'ArgosAggregation.BibliographyCLI.run()' -- --script"
      ]
    ]
  end
end
