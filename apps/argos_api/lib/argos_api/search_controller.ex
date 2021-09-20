defmodule ArgosAPI.SearchController do
  import Plug.Conn

  alias ArgosCore.ElasticSearch.DataProvider
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
    {:ok, %{"q" => Map.get(params, "q", "*")}}
    |> parse_positive_number(params, "size", "50", 10000)
    |> parse_positive_number(params, "from", "0", 10000)
    |> parse_filters(params, "filter")
    |> parse_filters(params, "!filter")
    |> finalize_query()
  end

  defp parse_positive_number({:ok, query}, params, name, default_value, max_value) do
    params
    |> Map.get(name, default_value)
    |> Integer.parse()
    |> case do
        {val, ""} when val >= max_value ->
          {:error, "Parameter '#{name}' exceeds maximum of #{max_value}: #{val}."}
        {val, ""} when val >= 0 ->
          {:ok, Map.put(query, name, val)}
        _ ->
          {:error, "Invalid '#{name}' parameter '#{params[name]}'."}
      end
  end

  defp parse_positive_number({:error, _} = error, _, _, _, _) do
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
              ["distance", params] ->
                parse_distance_filter(params)
              ["bounding_box", params] ->
                parse_bounding_box_filter(params)
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

  defp parse_distance_filter(opts) do
    with [lon, lat, dist] <- String.split(opts, ","),
      {longitude, _} <- Float.parse(lon),
      {latitude, _} <- Float.parse(lat),
      {distance, _} <- Float.parse(dist) do
      %{
        "geo_distance" => %{
          "distance" => "#{distance}km",
          "geometry" => %{
            "lat" => latitude,
            "lon" => longitude
          }
        }
      }
    else
      _e ->
        {:error, "Invalid distance filter query: #{inspect(opts)}. Please provide '<longitude>,<latidude>,<distance in km>'."}
    end
  end

  @generic_help "Please provide '<longitude(top left)>,<latitude(top left)>,<longitude(bottom right)>,<latitude(bottom right)>'."
  defp parse_bounding_box_filter(opts) do
    with [lon_a, lat_a, lon_b, lat_b] <- String.split(opts, ","),
      {topleft_longitude, _} <- Float.parse(lon_a),
      {topleft_latitude, _} <- Float.parse(lat_a),
      {bottom_right_longitude, _} <- Float.parse(lon_b),
      {bottom_right_latitude, _} <- Float.parse(lat_b) do

      cond do
        topleft_latitude < bottom_right_latitude ->
          {:error, "Invalid bounding box filter query: #{inspect(opts)}, top is below bottom corner. #{@generic_help}"}
        topleft_longitude > bottom_right_longitude ->
          {:error, "Invalid bounding box filter query: #{inspect(opts)}, longitude left is to the right. #{@generic_help}"}
        true ->
          %{
            "geo_bounding_box" => %{
              "geometry" => %{
                "top_left" => %{
                  "lat" => topleft_latitude,
                  "lon" => topleft_longitude
                },
                "bottom_right" => %{
                  "lat" => bottom_right_latitude,
                  "lon" => bottom_right_longitude
                }
              }
            }
          }
      end
    else
      _e ->
        {:error, "Invalid bounding box filter query: #{inspect(opts)}. #{@generic_help}"}
    end
  end

  defp finalize_query({:ok, %{"q" => q, "size" => size, "from" => from, "filter" => filters, "!filter" => must_not }}) do
    query =
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
        aggs: ArgosCore.ElasticSearch.Aggregations.aggregation_definitions()
      }
    { :ok, query }
  end
  defp finalize_query(error) do
    error
  end
end
