ExUnit.start()

defmodule ArgosHarvesting.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @elasticsearch_mapping_path Application.app_dir(:argos_core, "priv/elasticsearch-mapping.json")
  def create_index() do
    mapping = File.read!(@elasticsearch_mapping_path)

    case ArgosCore.HTTPClient.put(@elasticsearch_url) do
      {:error, error} -> raise error
      _ -> {:ok}
    end

    case ArgosCore.HTTPClient.put(
      "#{@elasticsearch_url}/_mapping",
      [{"Content-Type", "application/json"}],
      mapping
    ) do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end

  def refresh_index() do
    case ArgosCore.HTTPClient.get("#{@elasticsearch_url}/_refresh") do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end

  def remove_index() do
    case ArgosCore.HTTPClient.delete(@elasticsearch_url) do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end
end
