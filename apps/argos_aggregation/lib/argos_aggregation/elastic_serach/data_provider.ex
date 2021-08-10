defmodule ArgosAggregation.ElasticSearch.DataProvider do
  require Logger

  @base_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, ElasticSearch.Aggregations
  }

  def get_doc(doc_id) do
    Finch.build(:get, "#{@base_url}/_doc/#{doc_id}")
    |> Finch.request(ArgosAggregationFinchProcess)
    |> parse_response()
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

    Finch.build(:post, "#{@base_url}/_search", [{"Content-Type", "application/json"}], query)
    |> Finch.request(ArgosAggregationFinchProcess)
    |> parse_response()
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
    Finch.build(:post, "#{@base_url}/_search", @headers, query)
    |> Finch.request(ArgosAggregationFinchProcess)
  end

  defp parse_response({:ok, %Finch.Response{body: body}}) do
    Poison.decode(body)
  end

  defp extract_doc_from_response({:ok, %{"found" => false}}) do
    {:error, 404}
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

  defp transform_to_sparse_doc(doc) do
    # TODO: Cast to ecto schemas?
    # TODO: Strip full_record from doc and from topics
    doc
    |> Map.update!("core_fields", fn(core_fields) ->
      core_fields
      |> Map.update!("spatial_topics", &transform_topics_to_sparse_docs/1)
      |> Map.update!("general_topics", &transform_topics_to_sparse_docs/1)
      |> Map.update!("temporal_topics", &transform_topics_to_sparse_docs/1)
    end)
    |> strip_full_record_data()
    |> strip_geometry_data() # for place documents themselves also delete the geometry
  end

  defp transform_topics_to_sparse_docs(topics) do
    topics
    |> Enum.map(fn(topic) ->
      topic
      |> Map.update!("resource", &strip_geometry_data/1)
      |> Map.update!("resource", &strip_full_record_data/1)
    end)
  end

  defp strip_geometry_data(doc) do
    doc
    |> Map.delete("geometry")
  end

  defp strip_full_record_data(doc) do
    doc
    |> Map.update!("core_fields", fn(core_fields) ->
      core_fields
      |> Map.delete("full_record")
    end)
  end
end
