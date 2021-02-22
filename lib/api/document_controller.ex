defmodule Argos.API.DocumentController do

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)
  import Plug.Conn

  def get(conn) do
    response =
      "#{@elasticsearch_url}/_doc/#{conn.params["id"]}"
      |> HTTPoison.get([{"Content-Type", "application/json"}])
      |> handle_result()

    case response do
      {:ok, val} ->
        send_resp(conn, 200, Poison.encode!(val))
      {:error, 404} ->
        send_resp(conn, 404, Poison.encode!(%{message: "document not found"}))
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode(body)
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 404}}) do
    { :error, 404}
  end

end
