defmodule Argos.Data.Gazetteer do

  defmodule Place do
    alias Geo
    import DataModel.TranslatedContent

    @enforce_keys [:uri, :label]
    defstruct [:uri, :label, :geometry]
    @type t() :: %__MODULE__{
      uri: String.t(),
      label: [TranslatedContent.t()],
      geometry: [Geo.geometry()]
    }
  end

  require Logger

  defmodule DataProvider do

    alias DataModel.TranslatedContent

    @base_url Application.get_env(:argos, :gazetteer_url)
    @behaviour Argos.Data.GenericProvider

    @impl Argos.Data.GenericProvider
    def get_all() do
      []
    end

    @impl Argos.Data.GenericProvider
    def get_by_id(id) do
      "#{@base_url}/doc/#{id}.json"
      |> HTTPoison.get()
      |> parse_response()
      |> parse_place_data()
    end

    @impl Argos.Data.GenericProvider
    def get_by_date(%NaiveDateTime{} = _date) do
      []
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      body
      |> Poison.decode()
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end

    defp parse_response({:error, error}) do
      {:error, error.reason()}
    end

    defp parse_place_data({:ok, data}) do
      place =
        %Place{
          label: parse_names(data["names"]),
          uri: data["@id"],
          geometry: parse_geometries_as_geo_json(data["prefLocation"])
        }

      {:ok, place}
    end

    defp parse_place_data(error) do
      error
    end


    defp parse_names(nil) do
      []
    end

    defp parse_names(names) do
      names
      |> Enum.map(fn (%{"language" => lang, "title" => title}) ->
        %TranslatedContent{
          lang: lang,
          text: title
        }
      end)
    end

    defp parse_geometries_as_geo_json(data) do
      [
        data["coordinates"]
        |> create_point(),
        data["shape"]
        |> create_polygons()
      ]
      |> Enum.reject(fn val -> is_nil(val) end)
    end

    defp create_point(nil) do
      nil
    end

    defp create_point(coords) do
      Geo.JSON.encode!(
        %Geo.Point{ coordinates: List.to_tuple(coords) }
      )
    end

    defp create_polygons(nil) do
      nil
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

    # defp convert_shape([] = shape) do shape end
    # defp convert_shape([a,_] = shape) when is_number(a) do
    #   List.to_tuple(shape)
    # end
    # defp convert_shape([h|_] = shape) when is_list(h) do
    #   Enum.map(shape, &convert_shape/1)
    # end

    # def search!(query, limit, scroll) do
    #   params =  if is_boolean(scroll) do
    #     %{q: query, limit: limit, scroll: scroll}
    #   else
    #     %{q: query, limit: limit, scrollId: scroll}
    #   end

    #   HTTPoison.get!(search_url(), [], [{:params, params}])
    #   |> response_unwrap
    # end

    # def search(query) do
    #   HTTPoison.get!(search_url(), [], [{:params,  %{q: query}}])
    #   |> response_unwrap
    # end

    # defp search_url do
    #   "#{@base_url}"  <> "/search.json"
    # end

    # defp response_unwrap(%HTTPoison.Response{status_code: 200, body: body}) do
    #   Poison.decode!(body)
    # end

    # defp response_unwrap(    do
    #   raise "Gazetteer fetch returned unexpected '#{code}' on GET '#{url}'"
    # end
  end

  defmodule Harvester do
  #   @batch_size 100

  #   @doc """
  #   Loads data from gazetteer and saves it into the database
  #   """
  #   def harvest!(%Date{} = lastModified) do
  #     query = build_query_string(lastModified)
  #     total = harvest_batch!(query, @batch_size)
  #     total
  #   end

  #   defp build_query_string(%Date{} = date) do
  #     date_s = Date.to_iso8601(date)
  #     "(lastChangeDate:>=#{date_s})"
  #   end

  #   defp build_query_string(%{placeid: pid}) do
  #     "#{pid}"
  #   end


  #   defp harvest_batch!(query, batch_size) do
  #     total = case DataProvider.query!(query, batch_size, true) do

  #       # in case there is a scroll id start scrolling
  #       %{"scrollId" => scrollId} = response ->
  #         save_resources!(response)
  #         harvest_batch!(query, batch_size, scrollId)
  #         response["total"]

  #       # in every other case, try to save the response and return the total
  #       response ->
  #         save_resources!(response)
  #         response["total"]
  #     end

  #     total
  #   end

  #   defp harvest_batch!(query, batch_size, scroll_id) do
  #     case DataProvider.search!(query, batch_size, scroll_id) do
  #       %{"scrollId" => scrollId, "result" => results} = response  when results != [] ->
  #         save_resources!(response)
  #         harvest_batch!(query, batch_size, scrollId)
  #       response -> save_resources!(response)
  #     end
  #   end

  #   defp save_resources!(%{"result" => results}) when results != [] do
  #     Enum.map(results, &save_resource!(&1))
  #   end

  #   defp save_resources!(%{"result" => []}) do
  #     Logger.info("End of scroll/No result")
  #   end

  #   defp save_resources!(_) do
  #     raise "Unexpected response without field 'result'"
  #   end

  #   defp save_resource!( %{"gazId" => id} = result) do
  #     id = "gazetteer-#{id}"
  #     ElasticsearchClient.save!(result, id)
  #   end

  #   defp save_resource!(_) do
  #     raise "Unable to save malformed resource."
  #   end
  end
end
