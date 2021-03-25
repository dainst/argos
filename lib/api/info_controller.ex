defmodule Argos.API.InfoController do

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)
  import Plug.Conn

  def get(conn) do
    response =
      "#{@elasticsearch_url}"
      |> HTTPoison.get([{"Content-Type", "application/json"}])
      |> handle_result()
    #send_resp(conn, 400, response)
    case response do
      {:ok, body}->send_resp(conn, 400, Poison.encode!(%{name: body["name"], version: body["version"]}))
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do

    info = Poison.decode(body)
    IO.inspect(info)
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 404}}) do
    { :error, 404}
  end

end
