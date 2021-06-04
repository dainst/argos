defmodule ArgosAPI.Router do
  @moduledoc """
  Documentation for `ArgosAPI.Router` .
  """
  import Plug.Conn

  use Plug.Router

  if Mix.env == :dev do
    use Plug.Debugger, otp_app: :argos_api
  end

  plug CORSPlug
  plug :json_response
  plug :match
  plug :fetch_query_params
  plug :dispatch

  alias ArgosAPI.Errors

  get "/doc/:id" do
    ArgosAPI.DocumentController.get(conn)
  end

  get "/search" do
    ArgosAPI.SearchController.search(conn)
  end

  get "" do
    ArgosAPI.InfoController.get(conn)
  end

  match _ do
    Errors.send(conn, 404, "Requested page not found!")
  end

  def json_response(conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
  end
end
