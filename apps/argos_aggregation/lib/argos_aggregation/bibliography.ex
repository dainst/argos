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
  end

  defmodule BibliographicRecord do
    @enforce_keys [:id, :title, :persons, :institutions, :full_record]
    defstruct [:id, :title, :description, :subject, :spatial, :persons, :institutions, :full_record]
    @type t() :: %__MODULE__{
      id: String.t(),
      title: [TranslatedContent.t()],
      description: [TranslatedContent.t()],
      subject: [
        %{
          label: [TranslatedContent.t()],
          resource: Thesauri.Concept.t(),
        }
      ],
      spatial: [
        %{
          label: [TranslatedContent.t()],
          resource: Place.t()}
      ],
      persons: [Author.t()],
      institutions: [Author.t()],
      full_record: Map.t()
    }
  end

  require Logger

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :bibliography_url)
    @behaviour ArgosAggregation.AbstractDataProvider

    alias ArgosAggregation.Bibliography.BibliographyParser

    @impl ArgosAggregation.AbstractDataProvider
    def get_all() do
      %{
        "prettyPrint" => false
      }
      |> get_batches()
    end

    @impl ArgosAggregation.AbstractDataProvider
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
        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl ArgosAggregation.AbstractDataProvider
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
          query_params
          |> Map.put("page", 1)
          |> Map.put("limit", 100)
        end,
        fn (params) ->
          case process_batch_query(params) do
            {:error, reason} ->
              Logger.error("Error while processing batch. #{reason}")
              {:halt, params}
            [] ->
              {:halt, params}
            record_list ->
              Logger.info("Indexing page #{params["page"]}.")
              {
                record_list,
                params
                |> Map.update!("page", fn (old) -> old + 1 end)
              }
          end
        end,
        fn (params) ->
          Logger.info("Finished after #{params["page"]} pages.")
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
      request =
        Finch.build(
        :get,
        "#{@base_url}/api/v1/search?#{URI.encode_query(params)}",
        [ArgosAggregation.Application.get_http_user_agent_header()]
      )

      request
      |> Finch.request(ArgosFinch)
      |> parse_response(request)
    end

    defp parse_response({:ok, %Finch.Response{status: 200, body: body}}, _request) do
      { :ok, Poison.decode!(body) }
    end

    defp parse_response({:ok, %Finch.Response{status: code}}, request) do
      { :error, "Received status code #{code} for #{[request.host,request.path]}." }
    end

    defp parse_response({:error, error}) do
      { :error, error.reason() }
    end
  end

  defmodule BibliographyParser do
    def parse_record(record) do

      places =
        record["DAILinks"]["gazetteer"]
          |> Enum.map(&Task.async( fn -> parse_place(&1) end))
          |> Enum.map(&Task.await(&1, 1000 * 30))
          |> Enum.filter(fn val ->
            case val do
              {:error, _msg} ->
                false
              _place ->
                true
            end
          end)

      concepts =
        record["DAILinks"]["thesauri"]
        |> Enum.map(&Task.async( fn -> parse_concept(&1) end))
        |> Enum.map(&Task.await(&1, 1000 * 30))
        |> Enum.filter(fn val ->
          case val do
            {:error, _msg} ->
              false
            _concept ->
              true
          end
        end)

      %BibliographicRecord{
        id: record["id"],
        title: %TranslatedContent{
          text: record["title"],
          lang: NaturalLanguageDetector.get_language_key(record["title"])
        },
        description: parse_descriptions(record),
        persons: parse_persons(record),
        institutions: parse_institutions(record),
        spatial: places,
        subject: concepts,
        full_record: record
      }
    end

    defp parse_descriptions(record) do
      record["summary"]
      |> Enum.map(fn(summary) ->
        %TranslatedContent{
          text: summary,
          lang: NaturalLanguageDetector.get_language_key(summary)
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
        %Author{
          label: %TranslatedContent{
            text: name,
            lang: ""
          },
          uri: ""
        }
      end)
    end

    defp parse_institutions(record) do
      case record["authors"]["corporate"] do
        [] -> []
        map -> Map.keys(map)
      end
      |> Enum.map(fn name ->
        %Author{
          label: %TranslatedContent{
            text: name,
            lang: ""
          },
          uri: ""
        }
      end)
    end

    defp parse_place([]) do
      []
    end

    defp parse_place(data) do
      "https://gazetteer.dainst.org/place/" <> gaz_id = data["uri"]
      case Gazetteer.DataProvider.get_by_id(gaz_id) do
        {:ok, place} ->
          %{
            label: "Subject",
            resource: place
          }
        error ->
          Logger.error("Received error for #{data["uri"]}:")
          Logger.error(error)
          error
      end
    end

    defp parse_concept([]) do
      []
    end

    defp parse_concept(data) do
      "http://thesauri.dainst.org/" <> ths_id = data["uri"]
      case Thesauri.DataProvider.get_by_id(ths_id) do
        {:ok, concept} ->
          %{
            label: "Subject",
            resource: concept
          }
        error ->
          error
      end
    end
  end

  defmodule Harvester do

    use GenServer
    alias ArgosAggregation.ElasticSearchIndexer

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
      |> Enum.each(&ElasticSearchIndexer.index(&1))
    end

    def run_harvest(%DateTime{} = datetime) do
      DataProvider.get_by_date(datetime)
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end
  end
end
