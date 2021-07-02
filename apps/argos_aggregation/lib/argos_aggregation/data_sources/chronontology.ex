require Logger

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
    @field_type Application.get_env(:argos_aggregation, :chronontology_type_key)

    alias ArgosAggregation.NaturalLanguageDetector

    require Logger

    def get_all() do
      get_batches(%{})
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
        HTTPoison.get("#{@base_url}/data/period/#{id}")
        |> parse_response()

      case response do
        {:ok, data} ->
          parse_period_data(data)
        error ->
          error
      end
    end

    defp get_by_id_locally(id) do
      case ArgosAggregation.ElasticSearch.DataProvider.get_doc("temporal_concept_#{id}") do
        {:error, 404} ->
          get_by_id_from_source(id)
        {:ok, tc} ->
          {:ok, tc}
      end
     end

    def get_by_date(%Date{} = date) do
      get_batches(%{"q"=>"modified.date:[#{Date.to_iso8601(date)} TO *]"})
    end
    def get_by_date(%DateTime{} = date) do
      get_batches(%{"q"=>"modified.date:[#{DateTime.to_iso8601(date)} TO *]"})
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
      |> HTTPoison.get()
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
            parse_any_to_numeric_string(at)
          [%{"begin" => %{"notBefore" => notBefore}}] ->
            parse_any_to_numeric_string(notBefore)
          _ ->
            Logger.warning("Found no begin date for period #{data["resource"]["id"]}")
            ""
        end

      ending =
        case data["resource"]["hasTimespan"] do
          [%{"end" => %{"at" => at}}] ->
            parse_any_to_numeric_string(at)
          [%{"end" => %{"notAfter" => notAfter}}] ->
            parse_any_to_numeric_string(notAfter)
          _ ->
            Logger.warning("Found no end date for period #{data["resource"]["id"]}")
            ""
        end

      # TODO Gazetteer Place spatiallyPartOfRegion and hasCoreArea? https://chronontology.dainst.org/period/X5lOSI8YQFiL

      core_fields = %{
        "type" => @field_type,
        "source_id" => data["resource"]["id"],
        "uri" => "#{@base_url}/period/#{data["resource"]["id"]}",
        "title" => parse_names(data["resource"]["names"]),
        "description" => if(data["resource"]["description"]!=nil, do: [
          %{
            "lang" => NaturalLanguageDetector.get_language_key(data["resource"]["description"]),
            "text" => data["resource"]["description"]
          }
        ], else: [])
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

    def parse_any_to_numeric_string(string) when is_bitstring(string) do
      case Integer.parse(string) do
        {_val, _remainder} ->
          string
        :error ->
          ""
      end
    end

    def parse_any_to_numeric_string(_string) do
      ""
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
    use GenServer
    alias ArgosAggregation.ElasticSearch.Indexer

    @interval Application.get_env(:argos_aggregation, :temporal_concepts_harvest_interval)
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting chronontology harvester with an interval of #{@interval}ms.")

      Process.send(self(), :run, [])
      {:ok, state}
    end

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{})
    end

    def handle_info(:run, state) do # TODO: Übernommen, warum info und nicht cast/call?

      now = DateTime.now!(get_timezone())
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
      |> Stream.map(fn(val) ->
        case val do
          {:ok, data} ->
            data
          {:error, msg} ->
            Logger.error("Error while harvesting:")
            Logger.error(msg)
            nil
        end
      end)
      |> Stream.reject(fn(val) -> is_nil(val) end)
      |> Enum.each(&Indexer.index/1)
    end

    def run_harvest(%DateTime{} = datetime) do
      DataProvider.get_by_date(datetime)
      |> Stream.map(fn(val) ->
        case val do
          {:ok, data} ->
            data
          {:error, msg} ->
            Logger.error("Error while harvesting:")
            Logger.error(msg)
            nil
        end
      end)
      |> Stream.reject(fn(val) -> is_nil(val) end)
      |> Enum.each(&Indexer.index/1)
    end
  end
end
