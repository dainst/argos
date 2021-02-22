mapping = File.read!("priv/elasticsearch-mapping.json")

"#{Application.get_env(:argos, :elasticsearch_url)}"
|> HTTPoison.delete()
|> IO.inspect

"#{Application.get_env(:argos, :elasticsearch_url)}"
|> HTTPoison.put()

"#{Application.get_env(:argos, :elasticsearch_url)}/_mapping"
|> HTTPoison.put(mapping, [{"Content-Type", "application/json"}])
|> IO.inspect
