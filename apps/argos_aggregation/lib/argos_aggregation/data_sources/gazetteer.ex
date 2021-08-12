defmodule ArgosAggregation.Gazetteer do

  defmodule Place do
    use ArgosAggregation.Schema

    alias ArgosAggregation.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
      field :geometry, {:array, :map}
    end

    def changeset(place, params \\ %{}) do
      place
      |> cast(params, [:geometry])
      |> cast_embed(:core_fields)
      |> validate_required([:core_fields])
    end

    def create(params) do
      changeset(%Place{}, params)
      |> apply_action(:create)
    end
  end

  require Logger


  defmodule DataProvider do
    @batch_size 100

    @base_url Application.get_env(:argos_aggregation, :gazetteer_url)

    alias ArgosAggregation.Gazetteer.PlaceParser

    def get_all() do
      get_batches("*")
    end

    def get_by_id(id, force_reload \\ true) do
      case force_reload do
        true ->
          get_by_id_from_source(id)
        false ->
          get_by_id_locally(id)
      end
    end

    defp get_by_id_from_source(id) do
      response =
        Finch.build(:get, "#{@base_url}/doc/#{id}.json?shortLanguageCodes=true", [{"follow_redirect", "true"}], [])
        |> Finch.request(ArgosAggregationFinchProcess)
        |> parse_response()

      case response do
        {:ok, body} ->
          PlaceParser.parse_place(body)
        error ->
          error
      end
    end

    defp get_by_id_locally(id) do
      case ArgosAggregation.ElasticSearch.DataProvider.get_doc("place_#{id}") do
        {:ok, _} = place ->
          place
        {:error, 404} ->
          case get_by_id_from_source(id) do
            {:ok, place} = res ->
              ArgosAggregation.ElasticSearch.Indexer.index(place)
              res
            error->
              error
          end
      end
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
      |> run_search()
      |> parse_search_result()
    end
    defp process_batch_query(query, scroll_id, limit) do
      %{q: query, limit: limit, scrollId: scroll_id}
      |> run_search()
      |> parse_search_result()
    end

    defp parse_search_result({:error, reason}), do: {:error, reason}
    defp parse_search_result({:ok, %{"total" => 0}}), do: {:ok, []}
    defp parse_search_result({:ok, %{"result" => []}}), do: {:ok, []}
    defp parse_search_result({:ok, %{"result" => result, "scrollId" => scroll, "total" => total}}) do
      places =
        result
        |> Enum.map(&PlaceParser.parse_place/1)
      {:ok, %{result: places, scroll: scroll, total: total}}
    end

    defp run_search(params) do
      Finch.build(:get, "#{@base_url}/search.json?shortLanguageCodes=true&#{URI.encode_query(params)}")
      |> Finch.request(ArgosAggregationFinchProcess)
      |> parse_response()
    end

    defp parse_response({:ok, %Finch.Response{status: 200, body: body}}) do
      Poison.decode(body)
    end
    defp parse_response({:ok, %Finch.Response{status: code}}) do
      {:error, "Received unhandled status code #{code}."}
    end
    defp parse_response({:error, error}) do
      {:error, error}
    end
  end

  defmodule PlaceParser do
    @field_type Application.get_env(:argos_aggregation, :gazetteer_type_key)
    def parse_place(gazetteer_data) do
      core_fields = %{
        "type" => @field_type,
        "source_id" => gazetteer_data["gazId"],
        "uri" => gazetteer_data["@id"],
        "title" => parse_names([gazetteer_data["prefName"]] ++ Map.get(gazetteer_data, "names", [])),
        "full_record" => gazetteer_data
      }
      {
        :ok,
        %{
          "core_fields" => core_fields,
          "geometry" => parse_geometries_as_geo_json(gazetteer_data["prefLocation"])
        }
      }
    end

    defp parse_names(names) do
      names
      |> Enum.filter(fn (name) -> name != nil end)
      |> Enum.map(fn (entry) ->
        case entry do
          %{"language" => lang, "title" => title} ->
            %{
              "lang" => lang,
              "text" => title
            }
          %{"title" => title} ->
            %{
              "lang" => "",
              "text" => title
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

  defmodule Harvester do
    use GenServer
    alias ArgosAggregation.ElasticSearch.Indexer

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
      |> Enum.each(&index_place/1)
    end

    def run_harvest(%Date{} = date) do
      DataProvider.get_by_date(date)
      |> Enum.each(&index_place/1)
    end

    defp index_place({:ok, place}) do
      Indexer.index(place)
    end
    defp index_place({:error, err}) do
      Logger.error(err)
    end
    defp index_place(error) do
      Logger.error(error)
    end
  end
end
