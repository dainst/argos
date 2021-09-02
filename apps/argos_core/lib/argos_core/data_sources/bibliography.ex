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

    import SweetXml
    def get_all() do
      get_batches(%{})
    end


    def get_publications_link(zenon_id) do
      link =
        case get_journal_mappings() do
          {:ok, nil} ->
            {:ok, nil}
          {:ok, mapping} ->
            {:ok, mapping[zenon_id]}
          error ->
            error
        end

      if {:ok, nil} == link do
        # If journal mapping did not succeed, try books.
        case get_book_mappings() do
          {:ok, nil} ->
            {:ok, nil}
          {:ok, mapping} ->
            {:ok, mapping[zenon_id]}
          error ->
            error
        end
      else
        link
      end
    end

    def get_by_id(id) do
      result = ArgosCore.HTTPClient.get("#{@base_url}/api/v1/record?id=#{id}", :json)

      case result do
        {:ok, %{"records" => [record]}} ->
          record
          |> BibliographyParser.parse_record()
        {:error, %{
          body: "{\"status\":\"ERROR\",\"statusMessage\":\"Error loading record\"}",
          status: 400}
        } ->
          # For some reason VuFind returns a 400, with payload {"status": "ERROR", "statusMessage":
          # "Error loading record"} instead of 404.
          {:error, %{status: 404, body: "Error not found"}}
        error ->
          error
      end
    end

    def get_by_date(%DateTime{} = date) do
      encoded_date =
        date
        |> DateTime.truncate(:second)
        |> DateTime.to_string()
        |> String.replace(" ", "T")

      %{
        from: encoded_date
      }
      |> get_batches()
    end

    defp get_id_list_via_oai(params) do
      case params do
        %{resumptionToken: ""} ->
          {:halt, "No more records for query, stopping."}
        params ->
          xml_response =
            ArgosCore.HTTPClient.get(
              "#{@base_url}/OAI/Server?verb=ListRecords&metadataPrefix=oai_dc&#{URI.encode_query(params)}",
              :xml
            )

          case xml_response do
            {:ok, xml} ->
              if xpath(xml, ~x"/OAI-PMH/error[@code='noRecordsMatch']"o) != nil or xpath(xml, ~x"count(/OAI-PMH/ListRecords/record)"s) == "0" do
                {:halt, "No records matched OAI PMH parameters #{Poison.encode!(params)}."}
              else
                {
                  xpath(xml, ~x"//record/header[not(@status='deleted')]/identifier/text()"sl),
                  xpath(xml, ~x"//resumptionToken/text()"s),
                  xpath(xml, ~x"//resumptionToken/@completeListSize"s),
                  xpath(xml, ~x"count(/OAI-PMH/ListRecords/record)"s)
                }
              end
            error ->
              error
          end
      end
    end

    def get_batches(query_params) do
      Stream.resource(
        fn() ->
          %{
            query: query_params
          }
        end,
        fn(params) ->
          case params do
            %{overall_count: overall_count, current_count: current_count} ->
              Logger.info("Processed records: #{current_count} of possible #{overall_count}.")
            _ ->
              Logger.info("Starting bibliography harvest (Records marked as deleted are being ignored).")
          end

          oai_result =
            case get_id_list_via_oai(params[:query]) do
              {:halt, _} = halt ->
                halt
              {list, token, overall, record_count} ->
                query =
                  list
                  |> Enum.reduce("", fn( id, acc) ->
                  "id[]=#{id}&#{acc}"
                end)
                {query, token, overall, record_count}
            end

          records =
            case oai_result do
              {:halt, _} = halt ->
                halt
              {"", _, _, _} ->
                []
              {query, _, _, _} ->
                ArgosCore.HTTPClient.get(
                  "#{@base_url}/api/v1/record?#{query}",
                  :json
                )
                |> case do
                  {:ok, %{"records" => records}} ->
                    records
                  error ->
                    error
                end
                |> Stream.chunk_every(20) # Process in chunks to throttle the number of parallel processes
                |> Enum.map(fn(chunk) ->
                  chunk
                  |> Enum.map(&Task.async(fn -> BibliographyParser.parse_record(&1) end))
                  |> Enum.map(&Task.await(&1, 1000 * 60))
                end)
                |> List.flatten()
            end

          case records do
            {:halt, _} = halt ->
              halt
            val ->
              {_, token, overall_count, record_count} = oai_result

              {overall_count, _remainder} = Integer.parse(overall_count)
              {record_count, _remainder} = Integer.parse(record_count)

              {
                val,
                params
                |> Map.update!(:query, fn(query) ->
                  Map.put(query, :resumptionToken, token)
                end)
                |> Map.put_new(:overall_count, overall_count)
                |> Map.update(:current_count, 0, fn(last) ->
                  last + record_count
                end)
              }
          end
        end,
        fn(msg) ->
          case msg do
            msg when is_binary(msg) ->
              Logger.info(msg)
            %{current_count: current_count, overall_count: overall_count, query: _query} ->
              Logger.info("Stopped harvest after #{current_count} of possible #{overall_count} records.")
          end
        end
      )
    end

    def get_journal_mappings() do
      case Cachex.get(:argos_core_cache, :biblio_to_ojs_mappings) do
        {:ok, nil} ->
          response =
            ArgosCore.HTTPClient.get(
              "https://publications.dainst.org/journals/plugins/pubIds/zenon/api/index.php?task=mapping",
              :json
            )

          case response do
            {:ok, response} ->
              mapping = response["publications"]
              Cachex.put(:argos_core_cache, :biblio_to_ojs_mappings, mapping, ttl: :timer.seconds(60 * 30))
              {:ok, mapping}
            {:error, reason} = error ->
              Logger.error("Received #{reason} while tryig to load publications' journal mapping.")
              error
          end
        cached_value ->
          cached_value
      end
    end

    def get_book_mappings() do
      case Cachex.get(:argos_core_cache, :biblio_to_omp_mappings) do
        {:ok, nil} ->
          response =
            ArgosCore.HTTPClient.get(
              "https://publications.dainst.org/books/plugins/pubIds/zenon/api/index.php?task=mapping",
              :json
            )

          case response do
            {:ok, response} ->
              mapping = response["publications"]
              Cachex.put(:argos_core_cache, :biblio_to_omp_mappings, mapping, ttl: :timer.seconds(60 * 30))
              {:ok, mapping}
            {:error, %{status: status} = error} ->
              Logger.error("Received #{status} while trying to load publications' book mapping.")
              error
          end
        cached_value ->
          cached_value
      end
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
        |> Enum.map(&parse_place/1)
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
        |> Enum.map(&parse_concept/1)
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
        {:error, %{status: status} = msg} = error ->
            Logger.error("Received #{status} for #{data["uri"]}:")
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
        {:error, %{status: status} = msg} = error ->
          Logger.error("Received #{status} for #{data["uri"]}:")
          Logger.error(msg)
          error
      end
    end
  end
end
