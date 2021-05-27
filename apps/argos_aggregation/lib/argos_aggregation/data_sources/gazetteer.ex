defmodule ArgosAggregation.Gazetteer do

  defmodule Place do
    alias Geo
    alias ArgosAggregation.TranslatedContent

    @enforce_keys [:id, :uri, :label]
    defstruct [:id, :uri, :label, :geometry]
    @type t() :: %__MODULE__{
      id: Integer.t(),
      uri: String.t(),
      label: [TranslatedContent.t()],
      geometry: [Geo.geometry()]
    }

    def from_map(%{} = data) do
      %Place{
        id: data["id"],
        uri: data["uri"],
        label:
          data["label"]
          |> Enum.map(&TranslatedContent.from_map/1),
        geometry:
          data["geometry"]
          |> Enum.map(fn (data) ->
            data
            |> Geo.JSON.decode!()
            |> Geo.JSON.encode!()
          end)
      }
    end
  end

  require Logger

  defmodule PlaceParser do
    alias ArgosAggregation.TranslatedContent

    def parse_place({:ok, place}), do: place |> parse_place
    def parse_place(%{"@id" => id, "gazId" => gid, "names" => names, "prefName" => p_name, "prefLocation" => p_loc}) do
      {:ok,
        %Place{
          uri: id,
          id: gid,
          label: parse_names([p_name] ++ names),
          geometry: parse_geometries_as_geo_json(p_loc)
        }
      }
    end
    def parse_place(place_data) when not is_map_key(place_data, "names") and not is_map_key(place_data, "prefName") do
     Logger.warn("Male formated entry")
     {:error, "Male formated entry"}
    end
    def parse_place(place_data) when not is_map_key(place_data, "names") do
       Map.put(place_data, "names", []) |> parse_place
    end
    def parse_place(place_data) when not is_map_key(place_data, "prefLocation") do
      Map.put(place_data, "prefLocation", []) |> parse_place
    end
    def parse_place(place_data) when not is_map_key(place_data, "prefName") do
      Map.put(place_data, "prefName", %{}) |> parse_place
    end
    def parse_place(%{"@id" => id, "gazId" => gid, "names" => names, "prefName" => p_name, "prefLocation" => p_loc}) do
      {:ok,
        %Place{
          uri: id,
          id: gid,
          label: parse_names([p_name] ++ names),
          geometry: parse_geometries_as_geo_json(p_loc)
        }
      }
    end
    def parse_place(_data) do
      Logger.error("unsupported format")
      {:error, "unsupported format"}
    end

    defp parse_names(names) do
      names
      |> Enum.filter(fn (name) -> name != nil end)
      |> Enum.map(fn (entry) ->
        case entry do
          %{"language" => lang, "title" => title} ->
            %TranslatedContent{
              lang: lang,
              text: title
            }
          %{"title" => title} ->
            %TranslatedContent{
              lang: "",
              text: title
            }
          _ -> nil
        end
      end)
    end

    defp parse_geometries_as_geo_json(%{"coordinates" => coor, "shape" => shp}), do: [ create_point(coor), create_polygons(shp) ]
    defp parse_geometries_as_geo_json(%{"shape" => shp}),  do: [ create_polygons(shp)]
    defp parse_geometries_as_geo_json(%{"coordinates" => coor}), do: [ create_point(coor)]
    defp parse_geometries_as_geo_json(_),  do: []

    defp create_point(coords) do
      Geo.JSON.encode!(
        %Geo.Point{ coordinates: List.to_tuple(coords) }
      )
    end

    defp create_polygons(multi_polygon_list) do
      multi_polygon_list
      |> Enum.map(fn polygon_list ->
        polygon_list
        |> Enum.map(fn point_list ->
          point_list
          |> Enum.map(&List.to_tuple(&1))
        end)
      end)
      |> (fn val ->
        %Geo.MultiPolygon{coordinates: val}
      end).()
      |> Geo.JSON.encode!()
    end
  end

  defmodule DataProvider do
    @batch_size 100

    @base_url Application.get_env(:argos_aggregation, :gazetteer_url)

    def get_all() do
      get_batches("*")
    end

    def get_by_id(id) do
      "#{@base_url}/doc/#{id}.json?shortLanguageCodes=true"
      |> HTTPoison.get()
      |> parse_response()
      |> PlaceParser.parse_place
    end

    def get_by_date(%Date{} = date) do
      "(lastChangeDate:>=#{Date.to_iso8601(date)})"
      |> get_batches
    end

    defp get_batches(base_query) do
      Logger.debug("Starting batch query with q=#{base_query}.")
      Stream.resource(
        fn -> nil end,
        fn (scroll_id) ->
          case process_batch_query(base_query, scroll_id, @batch_size) do
            {:error, reason} ->
              Logger.error("Error while processing batch. #{reason}")
              {:halt, scroll_id}
            {:ok, []} ->
              {:halt, scroll_id}
            {:ok, %{result: results, scroll: scroll, total: total}} ->
              if is_nil(scroll_id) do
                Logger.debug("Found #{total} entries.")
              end
              {results, scroll}
          end
        end,
        fn (_scroll_id) ->
          Logger.debug("Finished scrolling batches.")
        end
      )
    end

    defp process_batch_query(query, nil, limit) do
      %{q: query, limit: limit, scroll: true}
      |> get_record_list
      |> handle_result
    end
    defp process_batch_query(query, scroll_id, limit) do
      %{q: query, limit: limit, scrollId: scroll_id}
      |> get_record_list
      |> handle_result
    end

    defp handle_result({:error, reason}), do: {:error, reason}
    defp handle_result({:ok, %{"total" => 0}}), do: {:ok, []}
    defp handle_result({:ok, %{"result" => []}}), do: {:ok, []}
    defp handle_result({:ok, %{"result" => result, "scrollId" => scroll, "total" => total}}) do
      places =
        result
        |> Task.async_stream(PlaceParser, :parse_place, [])
        |> Enum.flat_map(
          fn entry ->
            case entry do
              {:ok, {:ok, place}} -> [place]
              _ -> []
            end
          end)
      {:ok, %{result: places, scroll: scroll, total: total}}
    end

    defp get_record_list(params) do
      "#{@base_url}/search.json?shortLanguageCodes=true"
      |> HTTPoison.get([], [{:params, params}])
      |> parse_response
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}), do: Poison.decode(body)
    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end
    defp parse_response({:error, error}), do: {:error, error.reason()}

  end

  defmodule Harvester do
    use GenServer
    alias ArgosAggregation.ElasticSearchIndexer

    @interval Application.get_env(:argos_aggregation, :projects_harvest_interval)
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting gazetteer harvester with an interval of #{@interval}ms.")

      Process.send(self(), :run, [])
      {:ok, state}
    end

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{})
    end

    def handle_info(:run, state) do # TODO: Übernommen, warum info und nicht cast/call?
      now =
        DateTime.now!(get_timezone())
        |> DateTime.to_date()

      run_harvest(state.last_run)

      state = %{state | last_run: now}
      schedule_next_harvest()
      {:noreply, state}
    end

    defp schedule_next_harvest() do
      Process.send_after(self(), :run, @interval)
    end
    def run_harvest() do
      DataProvider.get_all()
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end

    def run_harvest(%Date{} = date) do
      DataProvider.get_by_date(date)
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end
  end
end
