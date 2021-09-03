# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application runtime (!) only evaluated by ArgosAPI configuration for release builds
import Config

config :argos_api,
  host_url: System.fetch_env!("HOST")

import_config "runtime.exs"
