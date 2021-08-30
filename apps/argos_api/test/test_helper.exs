ExUnit.start()

defmodule ArgosAPI.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @elasticsearch_mapping_path Application.app_dir(:argos_core, "priv/elasticsearch-mapping.json")

  def create_index() do

    case Finch.build(:put, @elasticsearch_url)
    |> Finch.request(ArgosAPIFinch) do
      {:error, error}-> raise error
      _-> {:ok}
   end
    mapping = File.read!(@elasticsearch_mapping_path)

    case Finch.build(:put, "#{@elasticsearch_url}/_mapping", [{"Content-Type", "application/json"}], mapping)
    |> Finch.request(ArgosAPIFinch) do
      {:error, error}-> raise error
      _-> {:ok}
   end
  end

  def refresh_index() do

    case Finch.build(:get, "#{@elasticsearch_url}/_refresh")
    |> Finch.request(ArgosAPIFinch) do
      {:error, error}-> raise error
      _-> {:ok}
   end
  end

  def remove_index() do

    case Finch.build(:delete, "#{@elasticsearch_url}")
    |> Finch.request(ArgosAPIFinch) do
      {:error, error}-> raise error
      _-> {:ok}
   end
  end
end
