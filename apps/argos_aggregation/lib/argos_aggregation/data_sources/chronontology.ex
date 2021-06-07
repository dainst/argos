defmodule ArgosAggregation.Chronontology do
  defmodule TemporalConcept do
    use ArgosAggregation.Schema

    alias ArgosAggregation.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
      field(:beginning, :integer)
      field(:ending, :integer)
    end

    def changeset(temporal_concept, params \\ %{}) do
      temporal_concept
      |> cast(params, [:beginning, :ending])
      |> cast_embed(:core_fields)
      |> validate_required([:core_fields])
    end

    def create(params) do
      changeset(%TemporalConcept{}, params)
      |> apply_action(:create)
    end
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :chronontology_url)

    alias ArgosAggregation.NaturalLanguageDetector

    require Logger

    def get_all() do
      get_batches(%{})
    end

    def get_by_id(id) do
      response =
        HTTPoison.get("#{@base_url}/data/period/#{id}")
        |> parse_response()

      case response do
        {:ok, data} ->
          parse_period_data(data)
        error ->
          error
      end
    end

    def get_by_date(%Date{} = date) do
      get_batches(%{"q"=>"modified.date:[#{Date.to_iso8601(date)} TO *]"})
    end

    def get_batches(query_params) do
      Stream.resource(
        fn () ->
          final_params =
            query_params
            |> Map.put("from", 0)
            |> Map.put("size", 100)

          Logger.info("Running chronontology batch query with for #{@base_url}/data/period?#{URI.encode_query(final_params)}")

          final_params
        end,
        fn (params) ->
          case process_batch_query(params) do
            {:error, reason} ->
              Logger.error("Error while processing batch. #{reason}")
              {:halt, params}
            [] ->
              {:halt, params}
            result_list ->
              Logger.info("Retrieving from #{params["from"]}.")
              {
                result_list,
                params
                |> Map.update!("from", fn (old) -> old + 100 end)
              }
          end
        end,
        fn (_params) ->
          Logger.info("Finished search.")
        end
      )
    end

    defp process_batch_query(params) do
      result =
        params
        |> get_list()

      case result do
        {:ok, %{"results" => results}} ->
          results
          |> Enum.map(&Task.async(fn -> parse_period_data(&1) end))
          |> Enum.map(&Task.await(&1, 1000 * 60))
        {:error, reason} ->
          {:error, reason}
      end
    end

    def get_list(params) do
      "#{@base_url}/data/period?#{URI.encode_query(params)}"
      |> HTTPoison.get([ArgosAggregation.Application.get_http_user_agent_header()])
      |> parse_response()
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

    defp parse_period_data(data) do
      # Zukunft: Es gibt potenziell mehrere timespan, wie damit umgehen?
      beginning =
        case data["resource"]["hasTimespan"] do
          [%{"begin" => %{"at" => at}}] ->
            parse_any_to_numeric(at)
          [%{"begin" => %{"notBefore" => notBefore}}] ->
            parse_any_to_numeric(notBefore)
          _ ->
            Logger.warning("Found no begin date for period #{data["resource"]["id"]}")
            ""
        end

      ending =
        case data["resource"]["hasTimespan"] do
          [%{"end" => %{"at" => at}}] ->
            parse_any_to_numeric(at)
          [%{"end" => %{"notAfter" => notAfter}}] ->
            parse_any_to_numeric(notAfter)
          _ ->
            Logger.warning("Found no end date for period #{data["resource"]["id"]}")
            ""
        end

      # TODO Gazetteer Place spatiallyPartOfRegion and hasCoreArea? https://chronontology.dainst.org/period/X5lOSI8YQFiL

      core_fields = %{
        "type" => "temporal_concept",
        "source_id" => data["resource"]["id"],
        "uri" => "#{@base_url}/period/#{data["resource"]["id"]}",
        "title" => parse_names(data["resource"]["names"]),
        "description" => [
          %{
            "lang" => NaturalLanguageDetector.get_language_key(data["resource"]["description"]),
            "text" => data["resource"]["description"] || ""
          }
        ]
      }

      {
        :ok,
        %{
          "core_fields" => core_fields,
          "beginning" => beginning,
          "ending" => ending
        }
      }
    end

    def parse_any_to_numeric(string) do
      case Integer.parse(string) do
        {_val, _remainder} ->
          string
        :error ->
          ""
      end
    end


    defp parse_names(chronontology_data) do
      chronontology_data
      |> Enum.map(fn {lang_key, name_variants} ->
        name_variants
        |> Enum.map(fn variant ->
          %{"text" => variant, "lang" => lang_key}
        end)
      end)
      |> List.flatten()
    end
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
