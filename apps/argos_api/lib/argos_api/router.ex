defmodule ArgosAPI.Router do
  @moduledoc """
  Documentation for `ArgosAPI.Router` .
  """
  import Plug.Conn

  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger, otp_app: :argos_api
  end

  plug :json_response
  plug :match
  plug :fetch_query_params
  plug :dispatch

  get "/doc/:id" do
    ArgosAPI.DocumentController.get(conn)
  end

  get "/search" do
    ArgosAPI.SearchController.search(conn)
  end

  match _ do
    send_resp(conn, 404, Poison.encode!(%{message: "Requested page not found!"}))
  end

  def json_response(conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
  end
end
