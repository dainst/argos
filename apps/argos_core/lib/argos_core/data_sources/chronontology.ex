require Logger

defmodule ArgosCore.Chronontology do
  defmodule TemporalConcept do
    use ArgosCore.Schema

    alias ArgosCore.CoreFields

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
    @base_url Application.get_env(:argos_core, :chronontology_url)
    @field_type Application.get_env(:argos_core, :chronontology_type_key)

    alias ArgosCore.NaturalLanguageDetector
    alias ArgosCore.Gazetteer

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
      response = ArgosCore.HTTPClient.get("#{@base_url}/data/period/#{id}", :json)

      case response do
        {:ok, data} ->
          parse_period_data(data)

        error ->
          error
      end
    end

    defp get_by_id_locally(id) do
      case ArgosCore.ElasticSearch.DataProvider.get_doc("temporal_concept_#{id}") do
        {:error, _} ->
          get_by_id_from_source(id)

        {:ok, tc} ->
          {:ok, tc}
      end
    end

    def get_by_date(%Date{} = date) do
      get_batches(%{"q" => "modified.date:[#{Date.to_iso8601(date)} TO *]"})
    end

    def get_by_date(%DateTime{} = date) do
      get_batches(%{"q" => "modified.date:[#{DateTime.to_iso8601(date)} TO *]"})
    end

    def get_batches(query_params) do
      Stream.resource(
        fn ->
          final_params =
            query_params
            |> Map.put("from", 0)
            |> Map.put("size", 100)

          Logger.info(
            "Running chronontology harvest with #{@base_url}/data/period?#{URI.encode_query(final_params)}."
          )

          final_params
        end,
        fn params ->
          case process_batch_query(params) do
            {:error, reason} ->
              raise(reason)

            [] ->
              {:halt, "No more records. Processed #{params["from"]}"}

            result_list ->
              if params["from"] != 0 do
                Logger.info("Processed #{params["from"]} records.")
              end

              {
                result_list,
                params
                |> Map.update!("from", fn old -> old + 100 end)
              }
          end
        end,
        fn msg ->
          case msg do
            msg when is_binary(msg) ->
              Logger.info(msg)

            %{"from" => from} ->
              Logger.info("Stopping. Processed #{from} records.")
          end
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

        error ->
          error
      end
    end

    def get_list(params) do
      ArgosCore.HTTPClient.get(
        "#{@base_url}/data/period?#{URI.encode_query(params)}",
        :json
      )
    end

    def parse_period_data(data) do
      # Zukunft: Es gibt potenziell mehrere timespan, wie damit umgehen?
      beginning =
        case data["resource"]["hasTimespan"] do
          [%{"begin" => %{"at" => at}}] ->
            parse_any_to_numeric_string(at)

          [%{"begin" => %{"notBefore" => notBefore}}] ->
            parse_any_to_numeric_string(notBefore)

          _ ->
            Logger.debug("Found no begin date for period #{data["resource"]["id"]}")
            ""
        end

      ending =
        case data["resource"]["hasTimespan"] do
          [%{"end" => %{"at" => at}}] ->
            parse_any_to_numeric_string(at)

          [%{"end" => %{"notAfter" => notAfter}}] ->
            parse_any_to_numeric_string(notAfter)

          _ ->
            Logger.debug("Found no end date for period #{data["resource"]["id"]}")
            ""
        end

      # TODO Gazetteer Place spatiallyPartOfRegion and hasCoreArea? https://chronontology.dainst.org/period/X5lOSI8YQFiL

      core_fields = %{
        "type" => @field_type,
        "source_id" => data["resource"]["id"],
        "uri" => "#{@base_url}/period/#{data["resource"]["id"]}",
        "title" => parse_names(data["resource"]["names"]),
        "description" =>
          if(data["resource"]["description"] != nil,
            do: [
              %{
                "lang" =>
                  NaturalLanguageDetector.get_language_key(data["resource"]["description"]),
                "text" => data["resource"]["description"]
              }
            ],
            else: []
          ),
        "spatial_topics" => parse_spatial_topics(data["resource"]),
        "full_record" => data
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

    defp parse_spatial_topics(chronontology_data) do
      part_of_region =
        Map.get(chronontology_data, "spatiallyPartOfRegion", [])
        |> create_spatial_topics([
          %{
            "lang" => "en",
            "text" => "is spatially part of region"
          },
          %{
            "lang" => "de",
            "text" => "ist räumlich Teil der Region"
          }
        ])

      core_area =
        Map.get(chronontology_data, "hasCoreArea", [])
        |> create_spatial_topics([
          %{
            "lang" => "en",
            "text" => "is spatially part of region"
          },
          %{
            "lang" => "de",
            "text" => "ist räumlich Teil der Region"
          }
        ])

      part_of_region ++ core_area
    end

    defp create_spatial_topics(urls, topic_context_notes) do
      urls
      |> Stream.map(fn url ->
        case url do
          "http://gazetteer.dainst.org/place/" <> gaz_id ->
            gaz_id

          _ ->
            nil
        end
      end)
      |> Stream.reject(&is_nil/1)
      |> Stream.map(&Gazetteer.DataProvider.get_by_id(&1, false))
      |> Enum.map(fn result ->
        case result do
          {:ok, place} ->
            %{
              "resource" => place,
              "topic_context_note" => topic_context_notes
            }

          {:error, msg} = error ->
            Logger.error("Received #{inspect(msg)}.")
            error
        end
      end)
    end
  end
end
