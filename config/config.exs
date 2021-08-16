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

  collections_url: "https://collections.idai.world",
  collections_harvest_interval: 1000 * 60 * 30, # 30 minutes
  collection_type_key: "collection",

  bibliography_url: "https://zenon.dainst.org",
  bibliography_harvest_interval: 1000 * 60 * 60 * 24, # Once a day (that is also zenon's update interval)
  bibliography_type_key: "biblio",

  chronontology_url: "https://chronontology.dainst.org",
  chronontology_type_key: "temporal_concept",
  temporal_concepts_harvest_interval: 1000 * 60 * 30, # 30 minutes

  gazetteer_url: "https://gazetteer.dainst.org",
  gazetteer_type_key: "place",

  thesauri_url: "http://thesauri.dainst.org",
  thesauri_type_key: "concept",

  active_harvesters: [
    ArgosAggregation.Collection.Harvester,
    ArgosAggregation.Bibliography.Harvester
  ]

port = 4001

config :argos_api,
  port: port,
  host_url: "http://localhost:#{port}"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
