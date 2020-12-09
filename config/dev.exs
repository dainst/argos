use Mix.Config

config :argos,
  elasticsearch_url: "localhost:9200/argos",
  projects_url: "localhost:4000",
  projects_harvest_interval: 1000 * 60 * 5 # 5 minutes
