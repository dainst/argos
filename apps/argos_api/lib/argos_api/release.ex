defmodule ArgosData.Release do
  require Logger
  @elasticsearch_url Application.get_env(:argos_api, :elasticsearch_url)
  @elasticsearch_mapping_path Application.get_env(:argos_api, :elasticsearch_mapping_path)

  def update_mapping() do
    HTTPoison.start()
    mapping = File.read!(@elasticsearch_mapping_path)

    clear_index()

    "#{@elasticsearch_url}/_mapping"
    |> HTTPoison.put(mapping, [{"Content-Type", "application/json"}])
    |> IO.inspect
  end

  def clear_index() do
    HTTPoison.start()

    "#{@elasticsearch_url}"
    |> HTTPoison.delete()

    "#{@elasticsearch_url}"
    |> HTTPoison.put()
  end
end
