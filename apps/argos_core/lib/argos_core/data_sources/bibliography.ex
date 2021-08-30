defmodule ArgosCore.Bibliography do

  alias ArgosCore.{
    Thesauri, Gazetteer, NaturalLanguageDetector
  }

  defmodule BibliographicRecord do
    use ArgosCore.Schema

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, ArgosCore.CoreFields)
    end

    def changeset(collection, params \\ %{}) do
      collection
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
    @base_url Application.get_env(:argos_core, :bibliography_url)

    alias ArgosCore.Bibliography.BibliographyParser
    def get_all() do
      %{
        "prettyPrint" => false
      }
      |> get_batches()
    end


    def get_publications_link(zenon_id) do
      case DataProvider.getJournalMappings() do
        {:ok, nil} -> case DataProvider.getBookMappings() do
          {:ok, books} ->
            {:ok, books["publications"][zenon_id]}
        end
        {:ok, journals} ->
          {:ok, journals["publications"][zenon_id]}
      end
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
      Finch.build(:get, "#{@base_url}/api/v1/search?#{URI.encode_query(params)}")
      |> Finch.request(ArgosCoreFinchProcess)
      |> parse_response()
    end

    defp parse_response({:ok, %Finch.Response{status: 200, body: body}}) do
      { :ok, Poison.decode!(body) }
    end
    defp parse_response({:ok, %Finch.Response{status: code}}) do
      { :error, "Received status code #{code}" }
    end
    defp parse_response({:error, error}) do
      { :error, error.reason() }
    end

    def getJournalMappings() do
      if !Cachex.get!(:bibliographyCache, "journalMapping") do
        case Finch.build(:get, "https://publications.dainst.org/journals/plugins/pubIds/zenon/api/index.php?task=mapping")
        |> Finch.request(ArgosAggregationFinchProcess)
        |> parse_response() do
          {:ok, response} -> Cachex.put(:bibliographyCache, "journalMapping", response, ttl: :timer.seconds(30))
          _ -> Logger.warn("Error while fetching journalMappings")
        end

      end
      Cachex.get(:bibliographyCache, "journalMapping")
    end
    def getBookMappings() do
      if !Cachex.get!(:bibliographyCache, "bookMapping") do
        case Finch.build(:get, "https://publications.dainst.org/books/plugins/pubIds/zenon/api/index.php?task=mapping")
        |> Finch.request(ArgosAggregationFinchProcess)
        |> parse_response() do
          {:ok, response} -> Cachex.put(:bibliographyCache, "bookMapping", response, ttl: :timer.seconds(30))
          _ -> Logger.warn("Error while fetching bookMappings")
        end

      end
      Cachex.get(:bibliographyCache, "bookMapping")
    end


  end

  defmodule BibliographyParser do
    @base_url Application.get_env(:argos_core, :bibliography_url)
    @field_type Application.get_env(:argos_core, :bibliography_type_key)

    def parse_record(record) do

      publications_links =
        case DataProvider.get_publications_link(record["id"]) do
          {:ok, nil} ->
            []
          {:ok, url} ->
            [%{
              "url" => url,
              "type" => :website,
              "label" => [%{"lang" => "en", "text" => "Available online"}, %{"lang" => "de", "text" => "Online verfügbar"}]
            }]
        end

      external_links =
        record["urls"]
        |> Enum.map(&parse_url(&1))

      external_links =
        publications_links ++ external_links
        |> Enum.uniq_by(fn(%{"url" => url}) -> url end)

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
        "external_links" => external_links,
        "full_record" => record
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

    defp parse_url(%{"url" => url, "desc" => desc}) do
      %{"url" => url,
        "type" => :website,
        "label" => case String.trim(desc)=="" do
          true->[%{"lang" => NaturalLanguageDetector.get_language_key(desc), "text" => desc}]
          _->[%{"lang" => NaturalLanguageDetector.get_language_key("External link"), "text" => "External link"}]
        end
      }
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
end
