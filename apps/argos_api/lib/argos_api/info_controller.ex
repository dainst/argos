defmodule ArgosAPI.InfoController do
  @elasticsearch_url Application.get_env(:argos_aggregation, :elasticsearch_url)
  @host_url Application.get_env(:argos_api, :host_url, "http://localhost:#{Application.get_env(:argos_api, :port)}")

  import Plug.Conn

  def get(conn) do
    argos_vsn = List.to_string(Application.spec(:argos_api, :vsn))

    %{"_all" => %{"total" => %{"docs" => %{"count" => count_docs }}}} =
      Finch.build(:get, "#{@elasticsearch_url}/_stats", [{"Content-Type", "application/json"}])
      |> Finch.request(ArgosAPIFinch)
      |> handle_result()

    info = %{
      argos_api_version: argos_vsn,
      records: count_docs,
      swagger_ui: "#{@host_url}/swagger",
      swagger_spec: "#{@host_url}/swagger/openapi.json"
    }

    send_resp(conn, 200, Poison.encode!(info))
  end

  defp handle_result({:ok, %Finch.Response{status: 200, body: body}}) do
    Poison.decode!(body)
  end
end
