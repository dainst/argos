defmodule ArgosAPI.SearchController do
  import Plug.Conn

  alias ArgosAggregation.ElasticSearch.DataProvider
  alias ArgosAPI.Errors

  def search(conn) do

    query = build_query(conn.params)

    case query do
      {:ok, query} ->

        result =
          Poison.encode!(query)
          |> DataProvider.run_query()
        case result do
          {:ok, val} ->
            send_resp(conn, 200, Poison.encode!(val))
          {:error, _} ->
            Errors.send(conn, 500)
        end
      {:error, msg} ->
        Errors.send(conn, 400, msg)
    end
  end

  defp build_query(params) do
    parsed_params =
      {:ok, %{"q" => Map.get(params, "q", "*")}}
      |> parse_positive_number(params, "size", "50")
      |> parse_positive_number(params, "from", "0")
      |> parse_filters(params, "filter")
      |> parse_filters(params, "!filter")

    case parsed_params do
      {:ok, %{"q" => q, "size" => size, "from" => from, "filter" => filters, "!filter" => must_not }} ->
        {
        :ok,
          %{
          query: %{
            bool: %{
              must: %{
                query_string: %{
                  query: q
                }
              },
              filter: filters,
              must_not: must_not
            }
          },
          size: size,
          from: from,
          aggs: ArgosAggregation.ElasticSearch.Aggregations.aggregation_definitions()
        }
      }
        error -> error
    end
  end

  defp parse_positive_number({:ok, query}, params, name, default_value) do
    params
    |> Map.get(name, default_value)
    |> Integer.parse()
    |> case do
        {val, ""} when val >= 0 ->
          {:ok, Map.put(query, name, val)}
        _ ->
          {:error, "Invalid size parameter '#{params[name]}'."}
      end
  end

  defp parse_positive_number({:error, _} = error, _, _, _) do
    error
  end

  defp parse_filters({:ok, query}, params, type) do

    parsing_result =
      params
      |> Map.get(type, [])
      |> case do
        values when is_list(values) ->
          values
          |> Enum.map(&String.split(&1, ":", parts: 2))
          |> Enum.map(fn split ->
            case split do
              [key, val] ->
                %{"term" => %{key => val}}
              _ ->
                {:error, "Invalid filter query: #{Plug.Conn.Query.encode(params)}. Expected a query like filter[]=<field>:<value>."}
            end
          end)
        _no_list ->
          [
            {:error, "Invalid filter query: #{Plug.Conn.Query.encode(params)}. Expected a list query like filter[]=<field>:<value>."}
          ]
      end


    parsing_result
    |> Enum.filter(&match?({:error, _}, &1))
    |> List.first()
    |> case do
      nil -> {:ok, Map.put(query, type, parsing_result)}
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_filters({:error, _} = error, _, _) do
    error
  end
end
