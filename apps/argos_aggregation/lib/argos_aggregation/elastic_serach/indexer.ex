defmodule ArgosAggregation.ElasticSearch.Indexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, Bibliography, CoreFields
  }

  @base_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  def index(data) do
    validation = validate(data)

    case validation do
      {:ok, struct} ->
        res =
          %{
            doc: struct,
            doc_as_upsert: true
          }
          |> upsert()
          |> parse_response()

        res_reference_update =
          res
          |> upsert_change?()
          |> update_referencing_data(struct)

        %{upsert_response: res, referencing_docs_update_response: res_reference_update}

      error ->
        error
    end

  end

  defp validate(%{"core_fields" => %{"type" => "place"}} = params) do
    Gazetteer.Place.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => "concept"}} = params) do
    Thesauri.Concept.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => "temporal_concept"}} = params) do
    Chronontology.TemporalConcept.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => "project"}} = params) do
    Project.Project.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => "biblio"}} = params) do
    Bibliography.BibliographicRecord.create(params)
  end

  def upsert(%{doc: %_{core_fields: %CoreFields{id: id}}} = data) do
    Logger.debug("Indexing #{id}.")

    data_json =
      data
      |> Poison.encode!

    "#{@base_url}/_update/#{id}?retry_on_conflict=5"
    |> HTTPoison.post(data_json, @headers)
  end
  defp parse_response({:ok, %HTTPoison.Response{body: body}}) do
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
    case ArgosAggregation.ElasticSearch.DataProvider.search_referencing_docs(updated_content) do
      :reference_search_not_implemented ->
        # Logger.debug("Reference search not implemented for #{updated_content.__struct__}. Nothing else gets updated.")
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

  defp update_reference(%{"_source" => parent }) do
    case parent["core_fields"] do
      %{"type" => "project"} = core_fields ->
        case Project.DataProvider.get_by_id(core_fields["source_id"]) do
          {:ok, project} ->
            index(project)
          error ->
            error
        end
      %{"type" => "biblio"} = core_fields ->
        case Bibliography.DataProvider.get_by_id(core_fields["source_id"]) do
          {:ok, biblio} ->
            index(biblio)
          error ->
            error
        end
      unhandled_reference ->
        msg = "Updating reference for type #{unhandled_reference["type"]} not implemented."
        Logger.error(msg)
        {:error, msg}
    end
  end
end
