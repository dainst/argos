ExUnit.start()

defmodule ArgosAggregation.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @elasticsearch_mapping_path Application.get_env(:argos_api, :elasticsearch_mapping_path)

  def create_index() do
    Finch.build(:put, @elasticsearch_url)
    |> Finch.request(ArgosFinch)

    mapping = File.read!("../../#{@elasticsearch_mapping_path}")

    Finch.build(:put, "#{@elasticsearch_url}/_mapping", [{"Content-Type", "application/json"}], mapping)
    |> Finch.request(ArgosFinch)
  end

  def refresh_index() do
    Finch.build(:get,  "#{@elasticsearch_url}/_refresh")
    |> Finch.request(ArgosFinch)
  end

  def remove_index() do
    Finch.build(:delete, "#{@elasticsearch_url}")
    |> Finch.request(ArgosFinch)
  end
end
