# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase


config :logger, :console,
  format: "$date $time [$level|$metadata] $message\n",
  metadata: [:module]

config :argos_core,
  elasticsearch_url: "http://localhost:9200",
  index_name: "argos",

  collections_url: "https://collections.idai.world",
  collection_type_key: "collection",

  bibliography_url: "https://zenon.dainst.org",
  bibliography_type_key: "biblio",

  chronontology_url: "https://chronontology.dainst.org",
  chronontology_type_key: "temporal_concept",

  gazetteer_url: "https://gazetteer.dainst.org",
  gazetteer_type_key: "place",

  thesauri_url: "http://thesauri.dainst.org",
  thesauri_type_key: "concept",

  mail_sender: {"Argos Status Mailer", "argos-status@idai.world"}

config :argos_core, ArgosCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: "mail.dainst.de",
  port: 587,
  tls: :if_available,
  allowed_tls_versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"],
  tls_log_level: :error,
  ssl: false,
  retries: 1,
  no_mx_lookups: false,
  auth: :always

port = 4001

config :argos_api,
  port: port,
  host_url: "http://localhost:#{port}"

config :argos_harvesting,
  bibliography_harvest_interval: 1000 * 60 * 60 * 24,
  collections_harvest_interval: 1000 * 60 * 60 * 24,
  chronontology_harvest_interval: 1000 * 60 * 60 * 24,
  gazetteer_harvest_interval: 1000 * 60 * 60 * 24,
  thesauri_harvest_interval: 1000 * 60 * 60 * 24

secrets_config_filename = "config.secrets.exs"
if not File.exists?("config/#{secrets_config_filename}") do
  File.copy!("config/config.secrets.exs_template", "config/#{secrets_config_filename}")
end

import_config(secrets_config_filename)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
