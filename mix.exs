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
    bibliography_seed_days_ago = 3
    gazetteer_seed_days_ago = 7
    [
      "update-mapping": [
        "run --eval 'ArgosCore.Release.update_mapping()' -- --script"
      ],
      seed: [
        "seed.bibliography", "seed.collections"
      ],
      "seed.bibliography": [
        "run --eval 'ArgosHarvesting.ReleaseCLI.seed(~s(bibliography), Date.utc_today() |> Date.add(-#{bibliography_seed_days_ago}) |> to_string())' -- --script"
      ],
      "seed.chronontology": [
        "run --eval 'ArgosHarvesting.ReleaseCLI.seed(~s(chronontology))' -- --script"
      ],
      "seed.collections": [
        "run --eval 'ArgosHarvesting.ReleaseCLI.seed(~s(collection))' -- --script"
      ],
      "seed.gazetteer": [
        "run --eval 'ArgosHarvesting.ReleaseCLI.seed(~s(gazetteer), Date.utc_today() |> Date.add(-#{gazetteer_seed_days_ago}) |> to_string())' -- --script"
      ],
      "seed.thesauri": [
        "run --eval 'ArgosHarvesting.ReleaseCLI.seed(~s(thesauri))' -- --script"
      ]
    ]
  end
end
