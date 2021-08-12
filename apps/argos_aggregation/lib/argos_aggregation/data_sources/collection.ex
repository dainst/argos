defmodule ArgosAggregation.Collection do
  require Logger

  alias ArgosAggregation.{
    Thesauri,
    Gazetteer,
    Chronontology
  }

  defmodule Collection do
    use ArgosAggregation.Schema

    alias ArgosAggregation.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
    end

    def changeset(collection, params \\ %{}) do
      collection
      |> cast(params, [])
      |> cast_embed(:core_fields)
      |> validate_required(:core_fields)
    end

    def create(params) do
      changeset(%Collection{}, params)
      |> apply_action(:create)
    end
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :collections_url)
    alias ArgosAggregation.Collection.CollectionParser

    alias ArgosAggregation.Gazetteer
    alias ArgosAggregation.Thesauri
    alias ArgosAggregation.Chronontology

    def get_all() do
      "#{@base_url}/api/projects"
      |> get_collection_list()
    end

    def get_by_date(%Date{} = date) do
      query =
        URI.encode_query(%{
          since: Date.to_string(date)
        })

      "#{@base_url}/api/projects?#{query}"
      |> get_collection_list()
    end

    def get_by_date(%DateTime{} = date) do
      query =
        URI.encode_query(%{
          since: DateTime.to_naive(date)
        })

      "#{@base_url}/api/projects?#{query}"
      |> get_collection_list()
    end

    defp get_collection_list(url) do
      result =
        Finch.build(:get, url)
        |> Finch.request(ArgosAggregationFinchProcess)
        |> handle_result()

      case result do
        {:ok, data} ->
          data
          |> Enum.map(&CollectionParser.parse_collection(&1))

        {:error, _} ->
          []
      end
    end

    def get_by_id(id) do
      result =
        Finch.build(:get, "#{@base_url}/api/projects/#{id}")
        |> Finch.request(ArgosAggregationFinchProcess)
        |> handle_result()

      case result do
        {:ok, data} ->
          CollectionParser.parse_collection(data)

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp handle_result({:ok, %Finch.Response{status: 200, body: body}} = _response) do
      case Poison.decode(body) do
        {:ok, %{"code" => 404}} ->
          {:error, 404}

        {:ok, data} ->
          {:ok, data["data"]}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp handle_result({_, %Finch.Response{status: 404}}) do
      {:error, 404}
    end

    defp handle_result({_, %Finch.Response{status: 400}}) do
      {:error, 400}
    end

    defp handle_result({:error, %Mint.HTTPError{reason: :econnrefused}}) do
      Logger.error("No connection to #{@base_url}")
      {:error, :econnrefused}
    end

    defp handle_result({:error, %Mint.HTTPError{reason: :timeout}}) do
      Logger.error("Timeout for #{@base_url}")
      {:error, :timeout}
    end
  end

  defmodule CollectionParser do
    @base_url Application.get_env(:argos_aggregation, :collections_url)
    @field_type Application.get_env(:argos_aggregation, :collection_type_key)

    def parse_collection(data) do
      external_links = parse_external_links(data["images"], data["external_links"])

      {spatial_topics, general_topics, temporal_topics} =
        parse_linked_resources(data["linked_resources"])

      {persons, organisations} = parse_stakeholders(data["stakeholders"])

      core_fields = %{
        "type" => @field_type,
        "source_id" => "#{data["id"]}",
        "uri" => "#{@base_url}/api/collections/#{data["id"]}",
        "title" => parse_translations(data["titles"]),
        "description" => parse_translations(data["descriptions"]),
        "external_links" => external_links,
        "general_topics" => general_topics,
        "spatial_topics" => spatial_topics,
        "temporal_topics" => temporal_topics,
        "persons" => persons,
        "organisations" => organisations,
        "full_record" => data
      }

      {
        :ok,
        %{
          "core_fields" => core_fields
        }
      }
    end

    defp parse_translations(translation_list) do
      translation_list
      |> Enum.map(fn value ->
        %{
          "lang" => value["language_code"],
          "text" => value["content"]
        }
      end)
    end

    defp parse_external_links(images, external_links) do
      image_links =
        images
        |> Enum.map(fn image ->
          %{
            "label" => parse_translations(image["labels"]),
            "url" => image["path"],
            "type" => :image
          }
        end)

      other_links =
        external_links
        |> Enum.map(fn image ->
          %{
            "label" => parse_translations(image["labels"]),
            "url" => image["url"],
            "type" => :website
          }
        end)

      image_links ++ other_links
    end

    defp parse_linked_resources(linked_resources) do
      grouped =
        linked_resources
        |> Enum.group_by(fn res ->
          res["linked_system"]
        end)

      spatial_topics =
        grouped
        |> Map.get("gazetteer", [])
        |> Enum.map(fn res ->
          case Gazetteer.DataProvider.get_by_id(res["res_id"], false) do
            {:ok, place} ->
              %{
                "topic_context_note" => parse_translations(res["descriptions"]),
                "resource" => place
              }
            {:error, msg} ->
              Logger.error(msg)
              nil
          end
        end)
        |> Enum.reject(fn(val) -> is_nil(val) end)

      general_topics =
        grouped
        |> Map.get("thesaurus", [])
        |> Enum.map(fn res ->
          case Thesauri.DataProvider.get_by_id(res["res_id"], false) do
            {:ok, concept} ->
              %{
                "topic_context_note" => parse_translations(res["descriptions"]),
                "resource" => concept
              }
            {:error, msg} ->
              Logger.error(msg)
              nil
          end
        end)
        |> Enum.reject(fn(val) -> is_nil(val) end)

      temporal_topics =
        grouped
        |> Map.get("chronontology", [])
        |> Enum.map(fn res ->
          case Chronontology.DataProvider.get_by_id(res["res_id"], false) do
            {:ok, tt} ->
              %{
                "topic_context_note" => parse_translations(res["descriptions"]),
                "resource" => tt
              }
            {:error, msg} ->
              Logger.error(msg)
              nil
          end
        end)
        |> Enum.reject(fn(val) -> is_nil(val) end)

      {spatial_topics, general_topics, temporal_topics}
    end

    defp parse_stakeholders(stakeholders) do
      persons =
        stakeholders
        |> Enum.map(fn person ->
          %{
            "name" =>
              case person do
                %{
                  "first_name" => first_name,
                  "last_name" => last_name,
                  "title" => ""
                } ->
                  "#{first_name} #{last_name}"

                %{
                  "first_name" => first_name,
                  "last_name" => last_name,
                  "title" => title
                } ->
                  "#{title} #{first_name} #{last_name}"

                %{
                  "first_name" => "",
                  "last_name" => last_name
                } ->
                  last_name

                _ ->
                  nil
              end,
            "uri" => person["orc_id"]
          }
        end)
        |> Enum.reject(fn person ->
          is_nil(person["name"])
        end)

      {persons, []}
    end
  end

  defmodule Harvester do
    use GenServer
    alias ArgosAggregation.ElasticSearch.Indexer

    @interval Application.get_env(:argos_aggregation, :collections_harvest_interval)
    # TODO Noch nicht refactored!
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting collections harvester with an interval of #{@interval}ms.")

      Process.send(self(), :run, [])
      {:ok, state}
    end

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{})
    end

    # TODO: Übernommen, warum info und nicht cast/call?
    def handle_info(:run, state) do
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
