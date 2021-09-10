# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application runtime (!) configuration for release builds
import Config

config :argos_api,
  host_url: System.fetch_env!("HOST")

config :argos_core, ArgosCore.Mailer,
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_USERPASSWORD")

config :argos_core,
  mail_recipient: {
    System.fetch_env!("MAILER_RECIPIENT_NAME"),
    System.fetch_env!("MAILER_RECIPIENT_ADDRESS")
  }
