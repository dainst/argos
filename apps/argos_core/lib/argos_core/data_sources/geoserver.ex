defmodule ArgosCore.Geoserver do
  defmodule MapRecord do
    use ArgosCore.Schema

    alias ArgosCore.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
      field :geometry, :map
    end

    def changeset(place, params \\ %{}) do
      place
      |> cast(params, [:geometry])
      |> cast_embed(:core_fields)
      |> validate_required([:core_fields])
    end

    def create(params) do
      changeset(%MapRecord{}, params)
      |> apply_action(:create)
    end
  end

  defmodule DataProvider do
    alias ArgosCore.Geoserver.MapRecordParser
    require Logger

    @base_url Application.get_env(:argos_core, :geoserver_url)

    def get_by_id(id) do
      "#{@base_url}/api/v2/layers/#{id}"
      |> ArgosCore.HTTPClient.get(:json)
      |> case do
        {:ok, response} ->
          response["layer"]
          |> MapRecordParser.parse()
        error ->
          error
      end
    end

    def get_all() do
      Stream.resource(
        fn ->
          :start
        end,
        fn(url) ->
          case url do
          :start ->
            "#{@base_url}/api/v2/layers"
            |> ArgosCore.HTTPClient.get(:json)
            |> process_result_page()
          nil ->
            {:halt, "No more records."}
          next ->
            next
            |> ArgosCore.HTTPClient.get(:json)
            |> process_result_page()
          end
        end,
        fn(msg) ->
          Logger.info(msg)
        end
      )
    end

    defp process_result_page(data) do
      case data do
        {:ok, %{"layers" => layers, "links" => %{"next" => next}}} ->
          {
            Enum.map(layers, &MapRecordParser.parse/1),
            next
          }
        error ->
          error
      end
    end
  end

  defmodule MapRecordParser do

    @field_type Application.get_env(:argos_core, :geoserver_type_key)

    alias ArgosCore.NaturalLanguageDetector
    def parse(data) do
      core_fields =
        %{
          "type" => @field_type,
          "source_id" => "#{data["pk"]}",
          "uri" => data["detail_url"],
          "title" => get_translated_content(data["title"]),
          "description" => get_descriptions(data),
          "external_links" => get_external_links(data),
          "persons" => get_persons(data),
          "full_record" => data
        }

      result = %{
        "core_fields" => core_fields
      }

      result =
        case Map.get(data, "bbox_polygon") do
          nil -> nil
          val -> %Geo.Polygon{
            coordinates:
              val["coordinates"]
              |> Enum.map(fn(coordinate) ->
                Enum.map(coordinate, fn(points) ->
                  List.to_tuple(points) # Geo.JSON.encode! insists on having points as tuples for some reason
                end)
              end)
          }
        end
        |> case do
          nil -> result
          poly ->
            Map.put(
              result,
              "geometry",
              Geo.JSON.encode!(
                %Geo.GeometryCollection{
                  geometries: [poly]
                }
              )
            )
        end
      {:ok, result}
    end

    defp get_translated_content(val) do
      [
        %{
          "text" => val,
          "lang" => NaturalLanguageDetector.get_language_key(val)
        }
      ]
    end

    defp get_descriptions(data) do
      abstract =
        case Map.get(data, "abstract") do
          nil -> []
          "" -> []
          "No abstract provided" -> []
          val -> get_translated_content(val)
        end
      purpose =
        case Map.get(data, "purpose") do
          nil -> []
          "" -> []
          val -> get_translated_content(val)
        end

      abstract ++ purpose
    end

    defp get_external_links(data) do
      thumbnail_link =
        case Map.get(data, "thumbnail_url") do
          nil -> []
          url -> [%{
            "label" => [%{
              "text" => "The map's thumbnail", "lang" => "en"
            }],
            "url" => url,
            "type" => :image
          }]
        end

      embed_link = case Map.get(data, "embed_url") do
        nil -> []
        url -> [%{
          "label" => [%{
            "text" => "Embed url for the map", "lang" => "en"
          }],
          "url" => url,
          "type" => :embed
        }]
      end

      thumbnail_link ++ embed_link
    end

    defp get_persons(data) do
      owner =
        case Map.get(data, "owner") do
          nil -> []
          %{"first_name" => first_name, "last_name" => last_name} ->
            [%{"name" => "#{first_name} #{last_name}"}]
        end

      poc =
        case Map.get(data, "poc") do
          nil -> []
          %{"first_name" => first_name, "last_name" => last_name} ->
            [%{"name" => "#{first_name} #{last_name}"}]
        end

      metadata_author =
        case Map.get(data, "metadata_author") do
          nil -> []
          %{"first_name" => first_name, "last_name" => last_name} ->
            [%{"name" => "#{first_name} #{last_name}"}]
        end

      owner ++ poc ++ metadata_author
      |> Enum.dedup()
    end
  end

end
