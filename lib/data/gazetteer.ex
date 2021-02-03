defmodule Argos.Data.Gazetteer do

  defmodule Place do
    alias Geo
    import DataModel.TranslatedContent

    @enforce_keys [:uri, :title]
    defstruct [:uri, :title, :geometry]
    @type t() :: %__MODULE__{
      uri: String.t(),
      title: TranslatedContent.t(),
      geometry: [Geo.geometry()]
    }
  end

  require Logger

  defmodule DataProvider do
    @base_url Application.get_env(:argos, :gazetteer_url)
    @behaviour Argos.Data.GenericProvider

    def search!(query, limit, scroll) do
      params =  if is_boolean(scroll) do
        %{q: query, limit: limit, scroll: scroll}
      else
        %{q: query, limit: limit, scrollId: scroll}
      end

      HTTPoison.get!(search_url(), [], [{:params, params}])
      |> response_unwrap
    end

    @impl Argos.Data.GenericProvider
    def search(query) do
      HTTPoison.get!(search_url(), [], [{:params,  %{q: query}}])
      |> response_unwrap
    end

    @impl Argos.Data.GenericProvider
    def get_by_id(%{id: id}) do
      query = "#{id}"
      %{"result" => result} = case HTTPoison.get(search_url(), [], [{:params,  %{q: query}}]) do
        {:ok, %HTTPoison.Response{} = response} ->
            response_unwrap(response)
        {:error, %HTTPoison.Error{reason: reason}} ->
            Logger.error("#{reason}")
            exit("Error during http request")
      end
      result
    end

    defp search_url do
      "#{@base_url}"  <> "/search.json"
    end

    defp response_unwrap(%HTTPoison.Response{status_code: 200, body: body}) do
      Poison.decode!(body)
    end

    defp response_unwrap(%HTTPoison.Response{status_code: code, request: %{url: url}}) do
      raise "Gazetteer fetch returned unexpected '#{code}' on GET '#{url}'"
    end
  end

  defmodule Harvester do
    @batch_size 100

    @doc """
    Loads data from gazetteer and saves it into the database
    """
    def harvest!(%Date{} = lastModified) do
      query = build_query_string(lastModified)
      total = harvest_batch!(query, @batch_size)
      total
    end


    defp build_query_string(%Date{} = date) do
      date_s = Date.to_iso8601(date)
      "(lastChangeDate:>=#{date_s})"
    end

    defp build_query_string(%{placeid: pid}) do
      "#{pid}"
    end


    defp harvest_batch!(query, batch_size) do
      total = case DataProvider.query!(query, batch_size, true) do

        # in case there is a scroll id start scrolling
        %{"scrollId" => scrollId} = response ->
          save_resources!(response)
          harvest_batch!(query, batch_size, scrollId)
          response["total"]

        # in every other case, try to save the response and return the total
        response ->
          save_resources!(response)
          response["total"]
      end

      total
    end

    defp harvest_batch!(query, batch_size, scroll_id) do
      case DataProvider.search!(query, batch_size, scroll_id) do
        %{"scrollId" => scrollId, "result" => results} = response  when results != [] ->
          save_resources!(response)
          harvest_batch!(query, batch_size, scrollId)
        response -> save_resources!(response)
      end
    end

    defp save_resources!(%{"result" => results}) when results != [] do
      Enum.map(results, &save_resource!(&1))
    end

    defp save_resources!(%{"result" => []}) do
      Logger.info("End of scroll/No result")
    end

    defp save_resources!(_) do
      raise "Unexpected response without field 'result'"
    end

    defp save_resource!( %{"gazId" => id} = result) do
      id = "gazetteer-#{id}"
      ElasticsearchClient.save!(result, id)
    end

    defp save_resource!(_) do
      raise "Unable to save malformed resource."
    end
  end

end
