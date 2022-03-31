defmodule ArgosCore.Gazetteer do

  defmodule Place do
    use ArgosCore.Schema

    alias ArgosCore.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
      field :geometry, :map
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

    @base_url Application.get_env(:argos_core, :gazetteer_url)

    alias ArgosCore.Gazetteer.PlaceParser

    def get_all() do
      get_batches("*")
    end

    defp check_redirect_for_id(id) do
      case Cachex.get(:argos_core_cache, :gazetteer_redirects) do

        {:ok, nil} ->
          id
        {:ok, redirects} ->
          case redirects[id] do
            nil ->
              id
            redirect ->
              Logger.debug("Used cached gazetteer redirect from #{id} to #{redirect}.")
              redirect
          end
      end
    end

    def get_by_id(id, force_reload \\ true) do
      id = check_redirect_for_id(id)

      case force_reload do
        true ->
          get_by_id_from_source(id)
        false ->
          get_by_id_locally(id)
      end
    end

    defp get_by_id_from_source(id) do
      response =
        ArgosCore.HTTPClient.get(
          "#{@base_url}/doc/#{id}.json?shortLanguageCodes=true",
          :json
        )

      case response do
        {:ok, %{status: 301, location: location}} ->
          %{"gaz_id" => gaz_id} = Regex.named_captures(~r/\/doc\/(?<gaz_id>\d+).json/, location)

          Logger.debug("Gazetteer redirect from #{id} to #{gaz_id}.")
          case Cachex.get(:argos_core_cache, :gazetteer_redirects) do
            {:ok, nil} ->
              Cachex.put(:argos_core_cache, :gazetteer_redirects, %{id => gaz_id}, ttl: :timer.seconds(60 * 15))
              Logger.debug("Created new cache for gazetteer redirects.")
            {:ok, redirects} ->
              redirects =
                redirects
                |> Map.put(id, gaz_id)
              Cachex.put(:argos_core_cache, :gazetteer_redirects, redirects, ttl: :timer.seconds(60 * 15))
              Logger.debug("Added entry to existing cache for gazetteer redirects.")
          end

          get_by_id(gaz_id)
        {:ok, body} ->
          PlaceParser.parse_place(body)
        error ->
          error
      end
    end

    defp get_by_id_locally(id) do
      case ArgosCore.ElasticSearch.DataProvider.get_doc("place_#{id}") do
        {:ok, _} = place ->
          place
        {:error, _} ->
          case get_by_id_from_source(id) do
            {:ok, place} = res ->
              ArgosCore.ElasticSearch.Indexer.index(place)
              res
            error->
              error
          end
      end
    end

    def get_by_date(%DateTime{} = date) do
      get_by_date(DateTime.to_date(date))
    end

    def get_by_date(%Date{} = date) do
      "(lastChangeDate:>=#{Date.to_iso8601(date)})"
      |> get_batches
    end

    defp get_batches(base_query) do
      Logger.info("Starting batch query with q=#{base_query}.")
      Stream.resource(
        fn -> %{scroll_id: nil} end,
        fn (%{scroll_id: scroll_id}) ->
          case process_batch_query(base_query, scroll_id, @batch_size) do
            {:error, reason} ->
              raise(reason)
            {:ok, []} ->
              {:halt, "No more records."}
            {:ok, %{result: results, scroll: scroll, total: total}} ->
              if is_nil(scroll_id) do
                Logger.info("Found #{total} entries.")
              else
                Logger.info("Processing next batch.")
              end
              {results, %{scroll_id: scroll}}
          end
        end,
        fn (msg) ->
          case msg do
            msg when is_binary(msg) ->
              Logger.info(msg)
            %{scroll_id: _scroll_id} ->
              Logger.info("Stopped without processing all records.")
          end
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
      ArgosCore.HTTPClient.get(
        "#{@base_url}/search.json?shortLanguageCodes=true&#{URI.encode_query(params)}",
        :json
      )
    end
  end

  defmodule PlaceParser do
    @field_type Application.get_env(:argos_core, :gazetteer_type_key)
    def parse_place(gazetteer_data) do
      core_fields = %{
        "type" => @field_type,
        "source_id" => gazetteer_data["gazId"],
        "uri" => gazetteer_data["@id"],
        "title" => parse_names([gazetteer_data["prefName"]] ++ Map.get(gazetteer_data, "names", [])),
        "full_record" => gazetteer_data
      }

      result =
        %{
          "core_fields" => core_fields,
        }

      # ElasticSearch does not allow empty :geometries for GeometryCollections, so
      # we do not add a "geometry" key to the Argos document if there are no geometries in the collection.
      result =
          %Geo.GeometryCollection{
            geometries: parse_geometries_as_geo_json(gazetteer_data["prefLocation"])
          }
          |> case do
            %{geometries: []} ->
              result
            values ->
              Map.put(
              result,
              "geometry",
              Geo.JSON.encode!(values)
            )
          end

      {:ok, result}

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
      %Geo.Point{ coordinates: List.to_tuple(coords) }
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
    end
  end
end
