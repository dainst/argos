defmodule ArgosAggregation.ElasticSearch.DataProvider do
  require Logger

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri
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

  def search_field(field_name, term) do
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

  defp extract_doc_from_response(%{"found" => false}) do
    {:error, 404}
  end
  defp extract_doc_from_response(%{"_source" => data}) do
    {:ok, data}
  end

  defp parse_response({:ok, %HTTPoison.Response{body: body}}) do
    Poison.decode!(body)
  end

end
