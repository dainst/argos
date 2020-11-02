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
  plug :fetch_query_params
  plug :dispatch
  plug :fetch_query_params

  get "/search" do
    query =
      conn
      |> build_query
      |> Poison.encode!
      |> IO.inspect

    result = HTTPoison.post("#{@elasticsearch_url}/_search", query, [{"Content-Type", "application/json"}])
      |> handle_result()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(result))
  end

  defp build_query(conn) do
    q =
      conn.params
      |>get_query_paramater("q", "*")

    {size, _} =
      conn.params
      |> get_query_paramater("size", "50")
      |> Integer.parse()

    from =
      case Integer.parse(get_query_paramater(conn.params, "from", "0")) do
        {val, _} when val > 10000 -> 10000
        {val, _} -> val
      end

    # TODO: Filter

    %{
      query: %{
        bool: %{
          must: %{
            query_string: %{
              query: q
            }
          },
          filter: [],
          must_not: []
        }
      },
      size: size,
      from: from
    }
  end

  defp get_query_paramater(params, key, default) do
    if Map.has_key?(params, key) do
      params[key]
    else
      default
    end
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode! body
  end

end
