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
    seed_days_ago = 3
    [
      "update-mapping": [
        "run --eval 'ArgosAggregation.Release.update_mapping()' -- --script"
      ],
      seed: [
        "seed.projects", "seed.bibliography"
      ],
      "seed.projects": [
        "run --eval 'ArgosAggregation.ProjectCLI.run()' -- --script"
      ],
      "seed.chronontology": [
        "run --eval 'ArgosAggregation.ChronontologyCLI.run()' -- --script"
      ],
      "seed.bibliography": [
        "run --eval 'ArgosAggregation.BibliographyCLI.run(
          DateTime.utc_now() |> DateTime.add(-60 * 60 * 24 * #{seed_days_ago}) |> DateTime.to_iso8601()
        )' -- --script"
      ]
    ]
  end
end
