# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :argos_aggregation,
  elasticsearch_url: "elasticsearch:9200",
  index_name: "argos",
  elasticsearch_mapping_path: "/elasticsearch-mapping.json"
