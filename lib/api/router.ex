defmodule Argos.API.Router do
  @moduledoc """
  Documentation for `Argos.API.Router` .
  """
  import Plug.Conn

  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger, otp_app: :argos
  end

  plug :json_response
  plug :match
  plug :fetch_query_params
  plug :dispatch

  get "/doc/:id" do
    Argos.API.DocumentController.get(conn)
  end

  get "/search" do
    Argos.API.SearchController.search(conn)
  end

  get "" do
    Argos.API.InfoController.get(conn)
  end

  match _ do
    send_resp(conn, 400, Poison.encode!(%{Version: ""}))
  end

  def json_response(conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
  end
end
