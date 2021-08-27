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

  get "/favicon.ico" do
    conn
    |> send_resp(204, "")
    |> put_resp_content_type("text/plain")
    |> halt()
  end

  get "/public/openapi.json" do
    # Because we want to set the API version dynamically for the main openapi document
    # the file is not served as a static asset in contrast to the other files in /public.
    api_spec =
      Application.app_dir(:argos_api, "priv/public/openapi.json")
      |> File.read!()
      |> Poison.decode!()
      |> Map.update!(
        "info",
        fn(info) ->
          info
          |> Map.update!(
            "version",
            fn(_) ->
              List.to_string(Application.spec(:argos_api, :vsn))
            end)
        end)

    send_resp(conn, 200, Poison.encode!(api_spec))
  end

  forward "/public", to: ArgosAPI.PublicFilesPlug
  forward "/swagger", to: OpenApiSpex.Plug.SwaggerUI, path: "/public/openapi.json"

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
