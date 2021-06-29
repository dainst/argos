# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :argos_aggregation,
  elasticsearch_mapping_path: "priv/elasticsearch-mapping.json",
  elasticsearch_url: "http://localhost:9200",
  index_name: "argos",

  projects_url: "http://projects.dainst.org",
  projects_harvest_interval: 1000 * 60 * 30, # 30 minutes

  bibliography_url: "https://zenon.dainst.org",
  bibliography_harvest_interval: 1000 * 60 * 30, # 30 minutes

  chronontology_url: "https://chronontology.dainst.org",
  temporal_concepts_harvest_interval: 1000 * 60 * 30, # 30 minutes
  gazetteer_url: "https://gazetteer.dainst.org",
  thesauri_url: "http://thesauri.dainst.org",
  active_harvesters: [
    ArgosAggregation.Project.Harvester,
    ArgosAggregation.Bibliography.Harvester
  ],

  bibliography_type: "biblio",
  chronontology_type: "temporal_concept",
  gazetteer_type: "place",
  project_type: "project",
  thesauri_type: "concept"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
