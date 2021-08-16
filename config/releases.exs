import Config

require Logger

config :argos_api,
  host_url: System.fetch_env!("HOST")
