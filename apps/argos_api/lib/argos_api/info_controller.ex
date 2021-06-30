defmodule ArgosAPI.InfoController do
  @elasticsearch_url Application.get_env(:argos_aggregation, :elasticsearch_url)
  import Plug.Conn

  def get(conn) do
    argos_vsn = List.to_string(Application.spec(:argos_api, :vsn))

    %{"hits" => %{"total" => %{"value" => count_docs }}} =
      "#{@elasticsearch_url}/_search?q=*&_source=false"
      |> HTTPoison.get([{"Content-Type", "application/json"}])
      |> handle_result()

    info = %{
      argos_api_version: argos_vsn,
      records: count_docs
    }

    send_resp(conn, 200, Poison.encode!(info))
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode!(body)
  end
end
