defmodule Argos.API.InfoController do

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)
  import Plug.Conn

  def get(conn) do
    response =
      "#{@elasticsearch_url}"
      |> HTTPoison.get([{"Content-Type", "application/json"}])
      |> handle_result()

    argos_vsn = List.to_string(Application.spec(:argos , :vsn))
    case response do
      {:ok, body}->send_resp(conn, 200, Poison.encode!(%{elastic_search: %{name: body["name"], version: body["version"]}, version: argos_vsn}))
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    info = Poison.decode(body)
  end

end
