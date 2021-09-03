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
          ],
          runtime_config_path: "config/runtime_api.exs"
        ],
        harvesting: [
          applications: [
            argos_harvesting: :permanent
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
    [
      {:poison, "~> 4.0", override: true}, # :api's open_api_spex dependency wants a lower poison version.
      {:mime, "~> 2.0.1", override: true}  # :core's bamboo dependency wants a lower mime version
    ]
  end

  defp aliases do
    seed_days_ago = 3
    [
      "update-mapping": [
        "run --eval 'ArgosCore.Release.update_mapping()' -- --script"
      ],
      seed: [
        "seed.collections", "seed.bibliography"
      ],
      "seed.collections": [
        "run --eval 'ArgosHarvesting.CollectionCLI.run()' -- --script"
      ],
      "seed.chronontology": [
        "run --eval 'ArgosHarvesting.ChronontologyCLI.run()' -- --script"
      ],
      "seed.bibliography": [
        "run --eval 'ArgosHarvesting.BibliographyCLI.run(
          DateTime.utc_now() |> DateTime.add(-60 * 60 * 24 * #{seed_days_ago}) |> DateTime.to_iso8601()
        )' -- --script"
      ]
    ]
  end
end
