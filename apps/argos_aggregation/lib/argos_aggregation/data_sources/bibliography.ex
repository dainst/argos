defmodule ArgosAggregation.Bibliography do

  alias ArgosAggregation.{
    Thesauri, Gazetteer, TranslatedContent, NaturalLanguageDetector
  }

  defmodule Author do
    @enforce_keys [:label]
    defstruct [:label, :uri]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      uri: String.t()
    }

    def from_map(%{} = data) do
      %Author{
        label: %TranslatedContent{
          text: data["label"]["text"],
          lang: data["label"]["lang"]
        },
        uri: data["uri"]
      }
    end
  end

  defmodule BibliographicRecord do
    use ArgosAggregation.Schema

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, ArgosAggregation.CoreFields)
    end

    def changeset(project, params \\ %{}) do
      project
      |> cast(params, [])
      |> cast_embed(:core_fields)
      |> validate_required(:core_fields)
    end

    def create(params) do
      changeset(%BibliographicRecord{}, params)
      |> apply_action(:create)
    end
  end

  require Logger

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :bibliography_url)

    alias ArgosAggregation.Bibliography.BibliographyParser
    def get_all() do
      %{
        "prettyPrint" => false
      }
      |> get_batches()
    end

    def get_by_id(id) do
      result =
        %{
          "prettyPrint" => false,
          "lookfor" => "id:#{id}"
        }
        |> get_record_list()

      case result do
        {:ok, %{"records" => [record]}} ->
          record
          |> BibliographyParser.parse_record()
        {:ok, %{"resultCount" => 0}} ->
          {:error, "record #{id} not found."}
        {:error, reason} ->
          {:error, reason}
      end
    end

    def get_by_date(%DateTime{} = date) do
      encoded_date =
        date
        |> DateTime.truncate(:second)
        |> DateTime.to_string()
        |> String.replace(" ", "T")

      %{
        "prettyPrint" => false,
        "daterange[]" => "last_indexed",
        "last_indexedfrom" => encoded_date,
        "last_indexedto" => "*"
      }
      |> get_batches
    end

    def get_batches(query_params) do
      Stream.resource(
        fn () ->
          final_params =
            query_params
            |> Map.put("page", 1)
            |> Map.put("limit", 100)

          Logger.info("Running bibliography batch query with for #{@base_url}/api/v1/search?#{URI.encode_query(final_params)}")

          final_params
        end,
        fn (params) ->
          case process_batch_query(params) do
            {:error, reason} ->
              Logger.error("Error while processing batch. #{reason}")
              {:halt, params}
            [] ->
              {:halt, params}
            record_list ->
              Logger.info("Retrieving page #{params["page"]}.")
              {
                record_list,
                params
                |> Map.update!("page", fn (old) -> old + 1 end)
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
        |> get_record_list()

      case result do
        {:ok, %{"records" => records}} ->
          records
          |> Enum.map(&Task.async(fn -> BibliographyParser.parse_record(&1) end))
          |> Enum.map(&Task.await(&1, 1000 * 60))
        {:ok, %{"resultCount" => _number}} ->
          # either empty search result (resultCount == 0) or search's last page + 1 (resultCount == n, but no record key)
          []
        {:error, reason} ->
          {:error, reason}
      end
    end

    def get_record_list(params) do
      "#{@base_url}/api/v1/search?#{URI.encode_query(params)}"
      |> HTTPoison.get()
      |> parse_response()
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      { :ok, Poison.decode!(body) }
    end
    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      { :error, "Received status code #{code} for #{req}." }
    end
    defp parse_response({:error, error}) do
      { :error, error.reason() }
    end
  end

  defmodule BibliographyParser do
    @base_url Application.get_env(:argos_aggregation, :bibliography_url)
    @field_type Application.get_env(:argos_aggregation, :bibliography_type_key)

    def parse_record(record) do

      spatial_topics =
        record["DAILinks"]["gazetteer"]
        |> Enum.map(&Task.async( fn -> parse_place(&1) end))
        |> Enum.map(&Task.await(&1, 1000 * 60 * 5))
        |> Enum.filter(fn val ->
          case val do
            {:error, _msg} ->
              false
            _place ->
              true
          end
        end)

      general_topics =
        record["DAILinks"]["thesauri"]
        |> Enum.map(&Task.async( fn -> parse_concept(&1) end))
        |> Enum.map(&Task.await(&1, 1000 * 60 * 5))
        |> Enum.filter(fn val ->
          case val do
            {:error, _msg} ->
              false
            _concept ->
              true
          end
        end)
      core_fields = %{
        "type" => @field_type,
        "source_id" => record["id"],
        "uri" => "#{@base_url}/Record/#{record["id"]}",
        "title" => [
          %{
            "text" => record["title"],
            "lang" => NaturalLanguageDetector.get_language_key(record["title"])
          }
        ],
        "general_topics" => general_topics,
        "spatial_topics" => spatial_topics,
        "description" => parse_descriptions(record),
        "persons" => parse_persons(record),
        "institutions" => parse_institutions(record),
      }

      {
        :ok,
        %{
          "core_fields" => core_fields
        }
      }
    end

    defp parse_descriptions(record) do
      record["summary"]
      |> Enum.map(fn(summary) ->
        %{
          "text" => summary,
          "lang" => NaturalLanguageDetector.get_language_key(summary)
        }
      end)
    end

    defp parse_persons(record) do
      primary =
        case record["authors"]["primary"] do
          [] -> []
          map -> Map.keys(map)
        end

      secondary =
        case record["authors"]["secondary"] do
          [] -> []
          map -> Map.keys(map)
        end

      primary ++ secondary
      |> Enum.uniq()
      |> Enum.map(fn name ->
        %{
          "name" => name
        }
      end)
    end

    defp parse_institutions(record) do
      case record["authors"]["corporate"] do
        [] -> []
        map -> Map.keys(map)
      end
      |> Enum.map(fn name ->
        %{
          "name" => name
        }
      end)
    end

    defp parse_place([]) do
      []
    end

    defp parse_place(data) do
      "https://gazetteer.dainst.org/place/" <> gaz_id = data["uri"]
      case Gazetteer.DataProvider.get_by_id(gaz_id, false) do
        {:ok, place} ->
          %{
            "resource" => place
          }
        {:error, msg} = error ->
          Logger.error("Received error for #{data["uri"]}:")
          Logger.error(msg)
          error
      end
    end

    defp parse_concept([]) do
      []
    end

    defp parse_concept(data) do
      "http://thesauri.dainst.org/" <> ths_id = data["uri"]
      case Thesauri.DataProvider.get_by_id(ths_id, false) do
        {:ok, concept} ->
          %{
            "resource" => concept
          }
        {:error, msg} = _error ->
          Logger.error("Received error for #{data["uri"]}:")
          Logger.error(msg)
          nil
      end
    end
  end

  defmodule Harvester do

    use GenServer
    alias ArgosAggregation.ElasticSearch.Indexer

    @interval Application.get_env(:argos_aggregation, :bibliography_harvest_interval)
    # TODO Noch nicht refactored!
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting bibliography harvester with an interval of #{@interval}ms.")

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
      |> Enum.map(&Task.async(fn -> Indexer.index(&1) end))
      |> Enum.map(&Task.await/1)
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
      |> Enum.map(&Task.async(fn -> Indexer.index(&1) end))
      |> Enum.map(&Task.await/1)
    end
  end
end
