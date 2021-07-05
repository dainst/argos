ExUnit.start()

defmodule ArgosAPI.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @elasticsearch_mapping_path Application.get_env(:argos_aggregation, :elasticsearch_mapping_path)

  def create_index() do

    HTTPoison.put!(@elasticsearch_url)

    mapping = File.read!("../../#{@elasticsearch_mapping_path}")

    HTTPoison.put!("#{@elasticsearch_url}/_mapping", mapping, [{"Content-Type", "application/json"}])
  end

  def refresh_index() do
    HTTPoison.get!("#{@elasticsearch_url}/_refresh")
  end

  def remove_index() do
    HTTPoison.delete!("#{@elasticsearch_url}")
  end
end
