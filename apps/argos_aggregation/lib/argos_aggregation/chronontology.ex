defmodule ArgosAggregation.Chronontology do

  defmodule TemporalConcept do
    alias ArgosAggregation.TranslatedContent

    @enforce_keys [:id, :uri, :label, :begin, :end]
    defstruct [:id, :uri, :label, :begin, :end]
    @type t() :: %__MODULE__{
      id: String.t(),
      uri: String.t(),
      label: TranslatedContent.t(),
      begin: integer(),
      end: integer()
    }
  end

  defmodule DataProvider do
    @behaviour ArgosAggregation.AbstractDataProvider
    @base_url Application.get_env(:argos_aggregation, :chronontology_url)

    require Logger

    @impl ArgosAggregation.AbstractDataProvider
    def get_all() do
      []
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_by_id(id) do
      HTTPoison.get("#{@base_url}/data/period/#{id}")
      |> parse_response()
      |> parse_period_data()
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_by_date(%Date{} = _date) do
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

    defp parse_period_data({:ok, data}) do
      # TODO: Es gibt potenziell mehrere timespan, wie damit umgehen?
      beginning =
        case data["resource"]["hasTimespan"] do
          [%{"begin" => %{"at" => at}}] ->
            at
          [%{"begin" => %{"notBefore" => notBefore}}] ->
            notBefore
          _ ->
            Logger.warning("Found no begin date for period #{data["resource"]["id"]}")
            ""
        end

      ending =
        case data["resource"]["hasTimespan"] do
          [%{"end" => %{"at" => at}}] ->
            at
          [%{"end" => %{"notAfter" => notAfter}}] ->
            notAfter
          _ ->
            Logger.warning("Found no end date for period #{data["resource"]["id"]}")
            ""
        end

      {:ok, %TemporalConcept{
        id: data["resource"]["id"],
        uri: "#{@base_url}/period/#{data["resource"]["id"]}",
        label: create_translated_content_list( data["resource"]["names"]),
        begin: beginning,
        end: ending
      }}
    end

    defp parse_period_data(error) do
      error
    end

    defp create_translated_content_list(%{} = tlc_map), do: Enum.map(tlc_map, &create_translated_content_list/1)
    defp create_translated_content_list({key, sub_list}), do: for val <- sub_list, do: %{lang: key, text: val}
    defp create_translated_content_list([] = tlc_list), do: tlc_list

    # def fetch!(query, offset, limit) do
    #   params = %{q: query, size: limit, from: offset}

    #   HTTPoison.get!(base_url(), [], [{:params, params}])
    #   |> response_unwrap
    # end

    # def fetch!(query) do
    #   HTTPoison.get!(base_url(), [], [{:params, %{q: query}}])
    #   |> response_unwrap
    # end

    # def fetch_by_id!(%{id: id}) do
    #   %{"results" => results} = HTTPoison.get!(base_url(), [], [{:params, %{q: id}}]) |> response_unwrap
    #   results
    # end

    # def fetch_total!(query) do
    #   case fetch!(query, 0, 0) do
    #     %{"total" => total} -> total
    #     _ -> raise "Unexpected response without a total."
    #   end
    # end

    # defp base_url do
    #   Application.get_env(:argos, :chronontology_url) <> "/period"
    # end

    # defp response_unwrap(%HTTPoison.Response{status_code: 200, body: body}) do
    #   Poison.decode!(body)
    # end

    # defp response_unwrap(%HTTPoison.Response{status_code: code, request: %{url: url}}) do
    #   raise "Chronontology fetch returned unexpected '#{code}' on GET '#{url}'"
    # end
  end

  defmodule Harvester do
    # require Logger
    # @batch_size 100

    # def harvest!(%Date{} = lastModified) do
    #   query = build_query_string(lastModified)

    #   total = ChronontologyClient.fetch_total!(query)
    #   offsets = Enum.filter(0..total, fn i -> rem(i, @batch_size) == 0 end)

    #   Enum.map(offsets, &harvest_batch!(query, &1, @batch_size))
    #   total
    # end

    # defp build_query_string(%Date{} = date) do
    #   date_s = Date.to_iso8601(date)
    #   "(modified.date:>=#{date_s}) OR (created.date:>=#{date_s})"
    # end

    # defp harvest_batch!(query, offset, batch_size) do
    #   ChronontologyClient.fetch!(query, offset, batch_size)
    #   |> save_resources!
    # end

    # defp save_resources!(%{"results" => results}) do
    #   Enum.map(results, &save_resource!(&1))
    # end

    # defp save_resources!(_) do
    #   raise "Unexpected response without field 'results'"
    # end

    # defp save_resource!(%{"resource" => %{"id" => id}} = result) do
    #   id = "chronontology-#{id}"
    #   ElasticsearchClient.save!(result["resource"], id)
    # end

    # defp save_resource!(_) do
    #   raise "Unable to save malformed resource."
    # end

    # def start_link(_opts) do
    #   GenServer.start_link(__MODULE__, %{})
    # end

    # def init(state) do
    #   state = Map.put(state, :last_run, Date.utc_today())
    #   Process.send(self(), :run, [])
    #   {:ok, state}
    # end

    # def handle_info(:run, state) do
    #   # Schedules a harvesting of chronontology datasets and sets the state.last_run
    #   # field to the date just before the harvesting started. Note that the chronontology
    #   # API does only support Date, not time granularity via an the Elasticsearch Range
    #   # query in a QueryString. This means that modified documents will be picked up by
    #   # the harvester more than once, if they changed on the date of a harvesting run.
    #   today = Date.utc_today()
    #   result = run_harvest(state.last_run)

    #   # A new harvest is scheduled regardless of the status of the last one
    #   schedule_next_harvest()

    #   # On error, do not update the state.last_run field, so that documents not
    #   # picked up in one run, might be picket up later.
    #   case result do
    #     {:ok, _} -> {:noreply, %{state | last_run: today}}
    #     {:error, _} -> {:noreply, state}
    #   end
    # end

    # def run_harvest(%Date{} = date) do
    #   # Gets all chronontology documents changed since the provided date and puts them
    #   # in our index.
    #   Logger.debug("Starting harvest for documents changed since: #{date}")

    #   try do
    #     total = ChronontologyHarvester.harvest!(date)
    #     Logger.debug("Successfully indexd #{total} documents changed since: #{date}")
    #     {:ok, nil}
    #   rescue
    #     e in RuntimeError ->
    #       Logger.error(e.message)
    #       {:error, e.message}
    #   end
    # end

    # defp schedule_next_harvest() do
    #   Process.send_after(self(), :run, interval())
    # end

    # defp interval do
    #   Application.get_env(:argos, :chronontology_harvest_interval)
    # end
  end
end
