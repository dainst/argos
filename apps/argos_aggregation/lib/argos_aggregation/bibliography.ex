defmodule ArgosAggregation.Bibliography do

  alias ArgosAggregation.{
    Thesauri, Gazetteer, TranslatedContent
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

    def get_all_test() do
      get_all()
      |> Enum.map(fn (record) ->
        :ok
      end)
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_all() do
      get_batches("prettyPrint=false")
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_by_id(id) do
      result =
        "lookfor=id:#{id}&prettyPrint=false"
        |> get_record_list()

      case result do
        {:ok, %{"records" => records}} ->
          records
          |> List.first()
          |> BibliographyParser.parse_record()
          |> IO.inspect
        {:error, reason} ->
          {:error, reason}
      end
    end

    def get_by_date_test() do
      DateTime.utc_now()
      |> DateTime.add(-60 * 60 * 24 * 5)
      |> get_by_date()
      |> Enum.map(fn (record) ->
        :ok
      end)
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_by_date(%DateTime{} = date) do
      encoded_date =
        date
        |> DateTime.truncate(:second)
        |> DateTime.to_string()
        |> String.replace(" ", "T")

      get_batches("prettyPrint=false&daterange[]=last_indexed&last_indexedfrom=#{encoded_date}&last_indexedto=*")
    end

    def get_batches(base_query) do
      Stream.resource(
        fn () ->
          1
        end,
        fn (page) ->
          case process_batch_query(base_query, page, 100) do
            {:error, reason} ->
              Logger.error("Error while processing batch. #{reason}")
              {:halt, page}
            [] ->
              {:halt, page}
            record_list ->
              Logger.info("Indexed #{page} pages.")
              {record_list, page + 1}
          end
        end,
        fn (page) ->
          Logger.info("Finished after #{page} pages.")
        end
      )
    end

    defp process_batch_query(base_query, page, limit) do
      result =
        "#{base_query}&page=#{page}&limit=#{limit}"
        |> get_record_list()

      case result do
        {:ok, %{"records" => records}} ->
          records
          |> Enum.map(&Task.async(fn -> BibliographyParser.parse_record(&1) end))
          |> Enum.map(&Task.await(&1))
        {:ok, %{"resultCount" => 0}} ->
          []
        {:error, reason} ->
          {:error, reason}
      end
    end

    def get_record_list(query) do
      "#{@base_url}/api/v1/search?#{query}"
      |> IO.inspect
      |> HTTPoison.get([{"User-Agent", ArgosAggregation.Application.get_http_agent()}])
      |> parse_response()
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      { :ok, Poison.decode!(body) }
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      { :error, "Received status code #{code} for #{req.url}." }
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
              {:ok, _place} ->
                true
              _ ->
                false
            end
          end)

      concepts =
        record["DAILinks"]["thesauri"]
        |> Enum.map(&Task.async( fn -> parse_concept(&1) end))
        |> Enum.map(&Task.await/1)
        |> Enum.filter(fn val ->
          case val do
            {:ok, _concept} ->
              true
            _ ->
              false
          end
        end)

      %BibliographicRecord{
        id: record["id"],
        title: %TranslatedContent{
          text: record["title"],
          lang: ""
        },
        persons: parse_persons(record),
        institutions: parse_institutions(record),
        spatial: places,
        subject: concepts,
        full_record: record
      }
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
      |> Enum.map(&ElasticSearchIndexer.index(&1))
      |> Enum.each(&Task.await/1)
    end

    def run_harvest(%DateTime{} = datetime) do
      DataProvider.get_by_date(datetime)
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end
  end
end
