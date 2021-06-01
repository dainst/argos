defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, Bibliography, CoreFields
  }

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  def index(data_struct) do
    res =
      %{
        doc: data_struct,
        doc_as_upsert: true
      }
      |> upsert()
      |> parse_response()

    res_reference_update =
      res
      |> upsert_change?()
      |> update_referencing_data(data_struct)

    %{upsert_response: res, referencing_docs_update_response: res_reference_update}
  end

  def upsert(%{doc: %_{core_fields: %CoreFields{id: id}}} = data) do
    Logger.debug("Indexing #{id}.")

    data_json =
      data
      |> Poison.encode!

    Finch.build(
      :post,
      "#{@base_url}/_update/#{id}",
      @headers,
      data_json
    )
    |> Finch.request(ArgosFinch)
  end

  defp parse_response({:ok, %Finch.Response{body: body}}) do
    Poison.decode!(body)
  end

  defp extract_search_hits_from_response(%{"hits" => %{"hits" => hits}}) do
    hits
  end

  defp upsert_change?(%{"result" => result}) do
    case result do
      "updated" -> true
      "created" -> true
      _ -> false
    end
  end

  defp update_referencing_data(true, updated_content) do
    case search_referencing_docs(updated_content) do
      :reference_search_not_implemented ->
        Logger.debug("Reference search not implemented for #{updated_content.__struct__}. Nothing else gets updated.")
        []
      res ->
        res
        |> parse_response()
        |> extract_search_hits_from_response()
        |> Enum.map(&update_reference(&1))
    end
  end

  defp update_referencing_data(false, _updated_content) do
    []
  end

  defp search_referencing_docs(%Gazetteer.Place{} = place) do
    search_for_subdocument(:spatial_topic, place.core_fields.source_id)
  end
  defp search_referencing_docs(%Chronontology.TemporalConcept{} = temporal) do
    search_for_subdocument(:temporal_topic, temporal.core_fields.source_id)
  end
  defp search_referencing_docs(%Thesauri.Concept{} = concept) do
    search_for_subdocument(:general_topic, concept.core_fields.source_id)
  end
  defp search_referencing_docs(_unknown_obj) do
    :reference_search_not_implemented
  end

  def search_for_subdocument(doc_type, doc_id) do
    query = Poison.encode!(%{
      query: %{
        query_string: %{
          query: "#{doc_id}",
            fields: ["#{doc_type}"]
          }
        }
      }
    )
    Finch.build(:post, "#{@base_url}/_search", @headers, query)
    |> Finch.request(ArgosFinch)
  end

  defp update_reference(%{"_source" => parent }) do
    case parent["core_fields"] do
      %{"type" => "project"} = core_fields ->
        Project.DataProvider.get_by_id(core_fields["source_id"])
        |> index()
      not_implemented ->
        Logger.error("Updating reference for type #{not_implemented["type"]}.")
    end
  end
end
