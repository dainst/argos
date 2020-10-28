defmodule Argos.Search do
  @moduledoc """
  Documentation for `Argos`.
  """
  import Plug.Conn

  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger, otp_app: :argos
  end

  require Logger

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)

  plug :match
  plug :dispatch

  get "/search" do
    conn = put_resp_content_type(conn, "application/json")
    result = HTTPoison.post("#{@elasticsearch_url}/_search", "", [{"Content-Type", "application/json"}])
      |> handle_result()

    send_resp(conn, 200, Poison.encode!(result))
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode! body
  end

end
