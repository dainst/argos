ExUnit.start()

defmodule ArgosCore.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @elasticsearch_mapping_path Application.get_env(:argos_core, :elasticsearch_mapping_path)

  def create_index() do
    mapping = File.read!("../../#{@elasticsearch_mapping_path}")

    case Finch.build(:put, @elasticsearch_url)
         |> Finch.request(ArgosCoreFinchProcess) do
      {:error, error} -> raise error
      _ -> {:ok}
    end

    case Finch.build(
           :put,
           "#{@elasticsearch_url}/_mapping",
           [{"Content-Type", "application/json"}],
           mapping
         )
         |> Finch.request(ArgosCoreFinchProcess) do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end

  def refresh_index() do
    case Finch.build(:get, "#{@elasticsearch_url}/_refresh")
         |> Finch.request(ArgosCoreFinchProcess) do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end

  def remove_index() do
    case Finch.build(:delete, "#{@elasticsearch_url}")
         |> Finch.request(ArgosCoreFinchProcess) do
      {:error, error} -> raise error
      _ -> {:ok}
    end
  end
end
