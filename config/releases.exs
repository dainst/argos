import Config

require Logger

config :argos_api,
  host: System.fetch_env!("HOST")
