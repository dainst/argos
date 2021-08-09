defmodule ArgosAPI.InfoController do
  @elasticsearch_url Application.get_env(:argos_aggregation, :elasticsearch_url)
  @host_url Application.get_env(:argos_api, :host_url, "http://localhost:#{Application.get_env(:argos_api, :port)}")

  import Plug.Conn

  def get(conn) do
    argos_vsn = List.to_string(Application.spec(:argos_api, :vsn))

    %{"_all" => %{"total" => %{"docs" => %{"count" => count_docs }}}} =
      "#{@elasticsearch_url}/_stats"
      |> HTTPoison.get([{"Content-Type", "application/json"}])
      |> handle_result()

    info = %{
      argos_api_version: argos_vsn,
      records: count_docs,
      swagger_ui: "#{@host_url}/swagger"
    }

    send_resp(conn, 200, Poison.encode!(info))
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode!(body)
  end
end
