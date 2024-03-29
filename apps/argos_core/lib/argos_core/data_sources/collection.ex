defmodule ArgosCore.Collection do
  require Logger

  alias ArgosCore.{
    Thesauri,
    Gazetteer,
    Chronontology
  }

  defmodule Collection do
    use ArgosCore.Schema

    alias ArgosCore.CoreFields

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
    @base_url Application.get_env(:argos_core, :collections_url)
    alias ArgosCore.Collection.CollectionParser

    alias ArgosCore.Gazetteer
    alias ArgosCore.Thesauri
    alias ArgosCore.Chronontology

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
      Logger.info("Starting collection harvest with #{url}.")
      result =
        ArgosCore.HTTPClient.get(
          url,
          :json
        )

      collections =
        case result do
          {:ok, data} ->
            data["data"]
            |> Enum.map(&CollectionParser.parse_collection(&1))
          {:error, reason} ->
            raise(reason)
        end
      Logger.info("Done.")
      collections
    end

    def get_by_id(id) do
      result =
        ArgosCore.HTTPClient.get(
          "#{@base_url}/api/projects/#{id}",
          :json
        )

      case result do
        # Rewrite 404 because Erga does not correctly set status code, see SD-1520
        {:ok, %{"code" => 404} = body} ->
          {:error, %{status: 404, body: body}}
        {:ok, data} ->
          CollectionParser.parse_collection(data["data"])
        error ->
          error
      end
    end
  end

  defmodule CollectionParser do
    @base_url Application.get_env(:argos_core, :collections_url)
    @field_type Application.get_env(:argos_core, :collection_type_key)

    def parse_collection(data) do
      external_links = parse_external_links(data["images"], data["external_links"])

      {spatial_topics, general_topics, temporal_topics} =
        parse_linked_resources(data["linked_resources"])

      {persons, organisations} = parse_stakeholders(data["stakeholders"])

      core_fields = %{
        "type" => @field_type,
        "source_id" => "#{data["id"]}",
        "uri" => "#{@base_url}/api/projects/#{data["id"]}",
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
end
