defmodule ArgosAggregation.ElasticSearch.DataProvider do
  require Logger

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, ElasticSearch.Aggregations
  }

  def get_doc(doc_id) do
    "#{@base_url}/_doc/#{doc_id}"
    |> HTTPoison.get()
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
    "#{@base_url}/_search"
    |> HTTPoison.post(query, [{"Content-Type", "application/json"}])
    |> handle_result()
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
    "#{@base_url}/_search"
    |> HTTPoison.post(query, @headers)
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

  defp parse_response({:ok, %HTTPoison.Response{body: body}}) do
    Poison.decode(body)
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    data =
      body
      |> Poison.decode()
      |> parse_search_response()
    {:ok, data}
  end

  defp handle_result(error) do
    error
  end

  defp parse_search_response({:ok, es_response}) do
    results =
      case es_response do
        %{"hits" => %{"hits" => list}} ->
          list
          |> Enum.map(fn(hit) ->
            Map.merge(%{"_id" => hit["_id"]}, hit["_source"])
          end)
        _ ->
          []
      end

    filters =
      es_response["aggregations"]
      |> Aggregations.reshape_search_result_aggregations()

    total =
      es_response["hits"]["total"]["value"]

    %{
      results: results,
      filters: filters,
      total: total
    }
  end
end
