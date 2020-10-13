defmodule Argos do
  @moduledoc """
  Documentation for `Argos`.
  """
  import Plug.Conn

  use Plug.Router
  require Logger

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)

  plug :match
  plug :dispatch

  get "/search" do
    HTTPoison.post("#{@elasticsearch_url}/_search", build_query_template('*', 10, 0), [{"Content-Type", "application/json"}])
    |> handle_result
    send_resp(conn, 200, "Welcome!")
  end

  get "/project/:id" do
    send_resp(conn, 200, "Project: #{id}")
  end

  defp build_query_template(q, size, from) do
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

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode! body
  end
  defp handle_result({:ok, %HTTPoison.Response{status_code: 400, body: body}}) do
    Logger.error "Elasticsearch query failed with status 400! Response: #{inspect body}"
    %{error: "bad_request"}
  end
  defp handle_result({:error, %HTTPoison.Error{reason: reason}}) do
    Logger.error "Elasticsearch query failed! Reason: #{inspect reason}"
    %{error: "unknown"}
  end
end
