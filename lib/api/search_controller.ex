defmodule Argos.API.SearchController do

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)

  import Plug.Conn

  def search(conn) do
    query =
      conn
      |> build_query
      |> Poison.encode!

    result =
      "#{@elasticsearch_url}/_search"
      |> HTTPoison.post(query, [{"Content-Type", "application/json"}])
      |> handle_result()

    case result do
      {:ok, val} ->
        send_resp(conn, 200, Poison.encode!(val))
    end
  end

  defp build_query(conn) do
    q =
      conn.params
      |> Map.get("q", "*")

    size =
      conn.params
      |> Map.get("size", "50")
      |> Integer.parse()
      |> case do
        {val, _} ->
          val
        :error ->
          50
      end

    from =
      Map.get(conn.params, "from", "0")
      |> Integer.parse()
      |> case do
        {val, _} ->
          val
        :error ->
          0
      end

    filters =
      conn.params
      |> Map.get("filter", [])
      |> parse_filters

    %{
      query: %{
        bool: %{
          must: %{
            query_string: %{
              query: q
            }
          },
          filter: filters,
          must_not: []
        }
      },
      size: size,
      from: from
    }
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    Poison.decode(body)
  end

  defp parse_filters([]) do
    []
  end

  defp parse_filters(requested_filters) do
    requested_filters
    |> Enum.map(&String.split(&1, ":", parts: 2))
    |> Enum.map(fn [key, val] ->
      %{"term" => %{key => val}}
    end)
  end
end
