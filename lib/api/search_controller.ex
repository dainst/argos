defmodule Argos.API.SearchController do

  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url)

  def run(conn) do
    query =
      conn
      |> build_query
      |> Poison.encode!

    "#{@elasticsearch_url}/_search"
    |> HTTPoison.post(query, [{"Content-Type", "application/json"}])
    |> handle_result()
  end


  defp build_query(conn) do
    # TODO: Filter

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


  defp get_query_paramater(params, key, default) do
    if Map.has_key?(params, key) do
      params[key]
    else
      default
    end
  end
end
