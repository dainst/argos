# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :logger, :console,
  format: "[$level] $message [$metadata]\n",
  metadata: [:application, :module]

config :argos_aggregation,
  bibliography_url: "http://zenon.dev.dainst.org"
