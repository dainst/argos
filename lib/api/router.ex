defmodule Argos.API.Router do
  @moduledoc """
  Documentation for `Argos.API.Router` .
  """
  import Plug.Conn

  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger, otp_app: :argos
  end

  plug :match
  plug :fetch_query_params
  plug :dispatch

  get "/search" do
    result = Argos.API.SearchController.search(conn)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(result))
  end

  match _ do
    send_resp(conn, 404, "Requested page not found!")
  end
end
