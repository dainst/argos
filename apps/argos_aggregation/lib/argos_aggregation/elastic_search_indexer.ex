defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project
  }
  alias ArgosAggregation.ElasticSearchIndexer.Updater
  alias ArgosAggregation.ElasticSearchIndexer.ElasticSearchClient

  def index(%Thesauri.Concept{} = concept) do
    payload =
      %{
        doc: Map.put(concept, :type, :concept),
        doc_as_upsert: true
      }

    call_elastic_client(payload)
    |> parse_response!()
    |> check_update(concept)
  end

  def index(%Gazetteer.Place{} = place) do
    payload =
      %{
        doc: Map.put(place, :type, :place),
        doc_as_upsert: true
      }

    call_elastic_client(payload)
    |> parse_response!()
    |> check_update(place)
  end

  def index(%Chronontology.TemporalConcept{} = temporal_concept) do
    payload =
      %{
        doc: Map.put(temporal_concept, :type, :temporal_concept),
        doc_as_upsert: true
      }

    call_elastic_client(payload)
    |> parse_response!()
    |> check_update(temporal_concept)
  end

  def index(%Project.Project{} = project) do
    payload =
      %{
        doc: Map.put(project, :type, :project),
        doc_as_upsert: true
      }

      ElasticSearchClient.upsert(payload)
      |> parse_response!()
  end

  def call_elastic_client(payload) do
    c = Application.get_env(:argos_aggregation, :elastic_client)
    c.upsert(payload)
  end

  defp parse_response!(%HTTPoison.Response{body: body}) do
    result = Poison.decode!(body)
    parse_response!(result)
  end
  defp parse_response!(%{"error" => error}), do: raise error
  defp parse_response!(result), do: result


  @doc """
  checks the result of the last action
  returns {:ok, "created"} or {:ok, "noop"} in those case
  in case of an update {:ok, "subdocs_updated"} or {:ok, "no_subdocuments"}
  """
  defp check_update(%{"result" => "updated"}, concept) do
    Logger.info("Apply Update")
    Updater.handle_update(concept)
  end
  defp check_update(%{"result" => "created"}, _obj) do
    {:ok, "created"}
  end
  defp check_update(%{"result" => "noop"}, _obj) do
    {:ok, "noop"}
  end
  defp check_update(_res, _obj) do
    {:error, "error in create/update process"}
  end


  defmodule ElasticSearchClient do
    @headers [{"Content-Type", "application/json"}]

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"

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

    def search_for_subdocument(doc_type, doc_id) do
      query = Poison.encode!(
          %{
            query: %{
              query_string: %{
                query: "#{doc_id}",
                  fields: ["#{doc_type}.resource.id"]
                }
              }
            }
          )
      res = "#{@base_url}/_search"
      |> HTTPoison.post(query, @headers)
      res
    end
  end


  defmodule Updater do

    def handle_update(resource) do
      find_relations(resource)
      |> handle_result
      |> change_all_subdocuments(resource)
      |> index
    end
    def index({:ok, msg}), do: {:ok, msg}
    def index([]), do: {:ok, "subdocs_updated"}
    def index([updated_doc|remain_docs]) do
      c = Application.get_env(:argos_aggregation, :elastic_client)
      payload = %{
        "doc" => updated_doc,
        "doc_as_upsert" => true
      }
      c.upsert(payload)
      index(remain_docs)
    end

    defp find_relations(%Gazetteer.Place{} = place), do: find_all_subdocuments(:spatial, place.id)
    defp find_relations(%Chronontology.TemporalConcept{} = temporal), do: find_all_subdocuments(:temporal, temporal.id)
    defp find_relations(%Thesauri.Concept{} = concept), do: find_all_subdocuments(:subject, concept.id)
    defp find_relations(_unknown_obj), do: {:error, "unsupported type"}

    defp find_all_subdocuments(concept_key, id) do
      c = Application.get_env(:argos_aggregation, :elastic_client)
      c.search_for_subdocument(concept_key, id)
    end

    def handle_result({:error, msg}), do: Logger.error(msg)
    def handle_result({:ok, nil}) do {:ok, :ok} end
    def handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      {:ok, %{"hits" => %{"hits" => hits }}} =
        body
        |> Poison.decode()
      {:ok, hits}
    end

    defp change_all_subdocuments({:ok, []}, _), do: {:ok, "no_subdocuments"}
    defp change_all_subdocuments({:ok, docs}, resource) do
      Enum.map(docs, &change_subdocument(&1, resource))
    end

    defp change_subdocument(%{"_source" => parent }, %Gazetteer.Place{} = place) do
      put_in(parent, ["spatial", Access.filter(&(&1["resource"]["id"] == place.id)), "resource"], place )
    end
    defp change_subdocument(%{"_source" => parent}, %Chronontology.TemporalConcept{} = temporal) do
      put_in(parent, ["temporal", Access.filter(&(&1["resource"]["id"] == temporal.id)), "resource"], temporal )
    end
    defp change_subdocument(%{"_source" => parent}, %Thesauri.Concept{} = subject) do
      put_in(parent, ["subject", Access.filter(&(&1["resource"]["id"] == subject.id)), "resource"], subject )
    end

  end

end
