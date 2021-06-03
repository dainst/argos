# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :argos_aggregation,
  await_index: false,
  active_harvesters: [
  ]

config :argos_api,
  index_name: "argos_testing"

config :logger, level: :info
