# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :argos_core,
  await_index: false,
  index_name: "argos_testing"

config :argos_api,
  await_index: false

config :logger, level: :warning
