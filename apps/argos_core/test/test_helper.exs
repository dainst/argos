ExUnit.start()

defmodule ArgosCore.TestHelpers do
  @elasticsearch_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @elasticsearch_mapping_path Application.app_dir(:argos_core, "priv/elasticsearch-mapping.json")

  def create_index() do
    remove_index()

    mapping = File.read!(@elasticsearch_mapping_path)

    ArgosCore.HTTPClient.put(@elasticsearch_url)

    ArgosCore.HTTPClient.put_payload(
      "#{@elasticsearch_url}/_mapping",
      [{"Content-Type", "application/json"}],
      mapping
    )

    refresh_index()
  end

  def refresh_index() do
    ArgosCore.HTTPClient.get("#{@elasticsearch_url}/_refresh")
  end

  def remove_index() do
    ArgosCore.HTTPClient.delete(@elasticsearch_url)
  end
end
