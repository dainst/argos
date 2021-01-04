use Mix.Config

config :argos,
  elasticsearch_url: "localhost:9200/argos",
  projects_url: "localhost:4000",
  projects_harvest_interval: 1000 * 60 * 5, # 5 minutes

  chronontology_url: "https://chronontology.dainst.org/data",
  chronontology_batch_size: 10,
  chronontology_harvest_interval: 1000 * 60 * 5 # 5 minutes,

  gazetteer_url: "https://gazetteer.dainst.org",
  gazetteer_batch_size: 10,
  gazetteer_harvest_interval: 1000 * 60 * 5 # 5 minutes
