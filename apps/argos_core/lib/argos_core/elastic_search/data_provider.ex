defmodule ArgosCore.ElasticSearch.DataProvider do
  require Logger

  @base_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  alias ArgosCore.{
    Chronontology, Gazetteer, Thesauri, ElasticSearch.Aggregations
  }

  def get_doc(doc_id) do
    ArgosCore.HTTPClient.get(
      "#{@base_url}/_doc/#{doc_id}", :json
    )
    |> extract_doc_from_response()
  end

  def search_referencing_docs(%Gazetteer.Place{} = place) do
    search_field("spatial_topic_id", place.core_fields.id)
  end
  def search_referencing_docs(%Chronontology.TemporalConcept{} = temporal) do
    search_field("temporal_topic_id", temporal.core_fields.id)
  end
  def search_referencing_docs(%Thesauri.Concept{} = concept) do
    search_field("general_topic_id", concept.core_fields.id)
  end
  def search_referencing_docs(_unknown_obj) do
    :reference_search_not_implemented
  end

  def run_query(query) do
    ArgosCore.HTTPClient.post(
      "#{@base_url}/_search",
      [{"Content-Type", "application/json"}],
      query,
      :json
    )
    |> extract_search_result_from_response()
  end

  defp search_field(field_name, term) do
    query = Poison.encode!(%{
      query: %{
        query_string: %{
          query: "#{term}",
            fields: ["#{field_name}"]
          }
        }
      }
    )
    ArgosCore.HTTPClient.post(
      "#{@base_url}/_search",
      @headers,
      query,
      :json
    )
  end

  defp extract_doc_from_response({:ok, %{"found" => false}}) do
    {:error, %{status: 404, body: %{"found" => false}}}
  end
  defp extract_doc_from_response({:ok, %{"_source" => data}}) do
    {:ok, data}
  end
  defp extract_doc_from_response(error) do
    error
  end

  defp extract_search_result_from_response({:ok, es_response}) do
    results =
      case es_response do
        %{"hits" => %{"hits" => list}} ->
          list
          |> Stream.map(fn(hit) ->
            Map.merge(%{"_id" => hit["_id"]}, hit["_source"])
          end)
          |> Enum.map(&transform_to_sparse_doc/1)
        _ ->
          []
      end

    filters =
      es_response["aggregations"]
      |> Aggregations.reshape_search_result_aggregations()

    total =
      es_response["hits"]["total"]["value"]

    {
      :ok,
      %{
        results: results,
        filters: filters,
        total: total
      }
    }
  end

  defp extract_search_result_from_response(error) do
    error
  end

  defp transform_to_sparse_doc(doc) do
    # TODO: Cast to ecto schemas?
    # The document and all linked 'topic'-documents are stripped down to their :core_fields.
    # Additionally the :full_record data is also removed.
    doc
    |> Map.update!("core_fields", fn(core_fields) ->
      core_fields
      |> Map.update!("spatial_topics", &transform_topics_to_sparse_docs/1)
      |> Map.update!("general_topics", &transform_topics_to_sparse_docs/1)
      |> Map.update!("temporal_topics", &transform_topics_to_sparse_docs/1)
    end)
    |> strip_to_core_fields()
    |> strip_full_record_data()
  end

  defp transform_topics_to_sparse_docs(topics) do
    topics
    |> Enum.map(fn(topic) ->
      topic
      |> Map.update!("resource", &transform_to_sparse_doc/1)
    end)
  end

  defp strip_to_core_fields(doc) do
    doc
    |> Map.take(["core_fields"])
  end

  defp strip_full_record_data(doc) do
    doc
    |> Map.update!("core_fields", fn(core_fields) ->
      core_fields
      |> Map.delete("full_record")
    end)
  end
end
