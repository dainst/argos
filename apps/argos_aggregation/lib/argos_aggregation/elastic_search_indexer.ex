defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, UpdateController.Observer
  }
  alias ArgosAggregation.ElasticSearchIndexer.Updater

  @headers [{"Content-Type", "application/json"}]

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  def index(%Thesauri.Concept{} = concept) do
    payload =
      %{
        doc:
          concept
          |> Map.put(:type, :concept),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
    |> check_update(concept)
  end

  def index(%Gazetteer.Place{} = place) do
    payload =
      %{
        doc:
          place
          |> Map.put(:type, :place),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
    |> check_update(place)
  end

  def index(%Chronontology.TemporalConcept{} = temporal_concept) do
    payload =
      %{
        doc:
          temporal_concept
          |> Map.put(:type, :temporal_concept),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
    |> check_update(temporal_concept)
  end

  def index(%Project.Project{} = project) do
    payload =
      %{
        doc: Map.put(project, :type, :project),
        doc_as_upsert: true
      }

      upsert(payload)
      |> parse_response!()
  end

  def upsert(%{doc: %{type: type, id: id}} = data) do
    Logger.info("Indexing #{type}-#{id}.")

    data_json =
      data
      |> Poison.encode!

    "#{@base_url}/_update/#{type}-#{id}"
    |> HTTPoison.post!(
      data_json,
      @headers
    )
  end

  def upsert(%{"doc" => %{"type" => type, "id" => id}} = data) do
    Logger.info("Indexing #{type}-#{id}.")

    data_json =
      data
      |> Poison.encode!

    "#{@base_url}/_update/#{type}-#{id}"
    |> HTTPoison.post!(
      data_json,
      @headers
    )
  end

  defp parse_response!(%HTTPoison.Response{body: body}) do
    result = Poison.decode!(body)
    parse_response!(result)
  end
  defp parse_response!(%{"error" => error}), do: raise error
  defp parse_response(result), do: result

  #defp check_update(%{"result" => "updated"}, kind, id) do
  #  Observer.updated_resource(:update_observer, kind, id)
  #end

  defp check_update(%{"result" => "updated"}, concept) do
    Updater.handle_update(concept)
  end
  defp check_update(_result, _obj) do
    {:ok, nil}
  end

  defmodule Updater do
    alias ArgosAggregation.ElasticSearchIndexer, as: Indexer

    @headers [{"Content-Type", "application/json"}]

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"

    def handle_update(resource) do
      find_relations(resource)
      |> handle_result
      |> Enum.each(&change_subdocument(&1, resource))
      |> Indexer.upsert
    end

    defp find_relations(%Gazetteer.Place{} = place), do: find_all_subdocuments(:spatial, place.id)
    defp find_relations(%Chronontology.TemporalConcept{} = temporal), do: find_all_subdocuments(:temporal, temporal.id)
    defp find_relations(%Thesauri.Concept{} = concept), do: find_all_subdocuments(:subject, concept.id)
    defp find_relations(_unknown_obj), do: {:error, "unsupported type"}

    defp find_all_subdocuments(concept_key, id) do
      query = get_query(concept_key, id)
      "#{@base_url}/_search"
      |> HTTPoison.post(query, @headers)
    end

    defp get_query(concept_key, id) do
      Poison.encode!(
        %{
          query: %{
            query_string: %{
              query: id,
                fields: ["#{concept_key}.resource.id"]
              }
            }
          }
        )
    end

    def handle_result({:error, msg}), do: Logger.error(msg)
    def handle_result({:ok, nil}) do {:ok, :ok} end
    def handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      {:ok, %{"hits" => %{"hits" => hits }}} =
        body
        |> Poison.decode()
      {:ok, hits}
    end

    defp change_subdocument(%{"_source" => parent }, %Gazetteer.Place{} = place) do
      put_in(parent, ["spatial", Access.all(), "resource", Access.filter(&(&1["id"] == place.id))], place )
    end
    defp change_subdocument(%{"_source" => parent}, %Chronontology.TemporalConcept{} = temporal) do
      put_in(parent, ["temporal", Access.all(), "resource", Access.filter(&(&1["id"] == temporal.id))], temporal )
    end
    defp change_subdocument(%{"_source" => parent}, %Thesauri.Concept{} = subject) do
      put_in(parent, ["subject", Access.all(), "resource", Access.filter(&(&1["id"] == subject.id))], subject )
    end

  end

end
