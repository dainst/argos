defmodule ArgosAPI.InfoController do
  @elasticsearch_url Application.get_env(:argos_core, :elasticsearch_url)
  @index_name Application.get_env(:argos_core, :index_name)
  import Plug.Conn

  def get(conn) do
    argos_vsn = List.to_string(Application.spec(:argos_api, :vsn))

    {:ok, %{"indices" => %{@index_name => %{"primaries" => %{"docs" => %{"count" => count_docs }}}}}} =
      ArgosCore.HTTPClient.get(
        "#{@elasticsearch_url}/_stats", :json
      )

    host_url = Application.get_env(:argos_api, :host_url)

    info = %{
      argos_api_version: argos_vsn,
      records: count_docs,
      swagger_ui: "#{host_url}/swagger",
      swagger_spec: "#{host_url}/public/openapi.json"
    }

    send_resp(conn, 200, Poison.encode!(info))
  end
end
