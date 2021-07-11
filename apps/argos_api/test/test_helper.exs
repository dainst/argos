ExUnit.start()

defmodule ArgosAPI.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @elasticsearch_mapping_path Application.get_env(:argos_aggregation, :elasticsearch_mapping_path)

  def create_index() do

    case Finch.build(:put, @elasticsearch_url)
    |> Finch.request(ArgosFinch) do
      {:error, error}-> raise error
   end
    mapping = File.read!("../../#{@elasticsearch_mapping_path}")


    case Finch.build(:put, "#{@elasticsearch_url}/_mapping", [{"Content-Type", "application/json"}], mapping)
    |> Finch.request(ArgosFinch) do
      {:error, error}-> raise error
   end
  end

  def refresh_index() do

    case Finch.build(:get, "#{@elasticsearch_url}/_refresh")
    |> Finch.request(ArgosFinch) do
      {:error, error}-> raise error
   end
  end

  def remove_index() do

    case Finch.build(:delete, "#{@elasticsearch_url}")
    |> Finch.request(ArgosFinch) do
      {:error, error}-> raise error
   end
  end
end
