defmodule ArgosCore.ElasticSearch.Indexer do
  require Logger
  alias ArgosCore.{
    Chronontology, Gazetteer, Thesauri, Collection, Bibliography, CoreFields, Geoserver
  }
  @base_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @headers [{"Content-Type", "application/json"}]
  @gazetteer_type_key Application.get_env(:argos_core, :gazetteer_type_key)
  @thesauri_type_key Application.get_env(:argos_core, :thesauri_type_key)
  @chronontology_type_key Application.get_env(:argos_core, :chronontology_type_key)
  @collection_type_key Application.get_env(:argos_core, :collection_type_key)
  @bibliography_type_key Application.get_env(:argos_core, :bibliography_type_key)
  @geoserver_type_key Application.get_env(:argos_core, :geoserver_type_key)

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

        res_reference_update =
          res
          |> upsert_change?()
          |> update_referencing_data(struct)

        %{upsert_response: res, referencing_docs_update_response: res_reference_update}

      error ->
        error
    end

  end

  defp validate(%{"core_fields" => %{"type" => @gazetteer_type_key}} = params) do
    Gazetteer.Place.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => @thesauri_type_key}} = params) do
    Thesauri.Concept.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => @chronontology_type_key}} = params) do
    Chronontology.TemporalConcept.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => @collection_type_key}} = params) do
    Collection.Collection.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => @bibliography_type_key}} = params) do
    Bibliography.BibliographicRecord.create(params)
  end
  defp validate(%{"core_fields" => %{"type" => @geoserver_type_key}} = params) do
    Geoserver.MapDocument.create(params)
  end

  def upsert(%{doc: %_{core_fields: %CoreFields{id: id}}} = data) do
    Logger.debug("Indexing #{id}.")

    data_json =
      data
      |> Poison.encode!

    ArgosCore.HTTPClient.post(
      "#{@base_url}/_update/#{id}?retry_on_conflict=5",
      @headers,
      data_json,
      :json
    )
  end

  defp extract_search_hits_from_response({:ok, %{"hits" => %{"hits" => hits}}}) do
    hits
  end

  defp upsert_change?({:ok, %{"result" => result}}) do
    case result do
      "updated" -> true
      "created" -> true
      _ -> false
    end
  end

  defp update_referencing_data(true, updated_content) do
    case ArgosCore.ElasticSearch.DataProvider.search_referencing_docs(updated_content) do
      :reference_search_not_implemented ->
        # Logger.debug("Reference search not implemented for #{updated_content.__struct__}. Nothing else gets updated.")
        []
      res ->
        res
        |> extract_search_hits_from_response()
        |> Enum.map(&update_reference(&1))
    end
  end

  defp update_referencing_data(false, _updated_content) do
    []
  end

  defp update_reference(%{"_source" => parent }) do
    case parent["core_fields"] do
      %{"type" => @collection_type_key} = core_fields ->
        case Collection.DataProvider.get_by_id(core_fields["source_id"]) do
          {:ok, collection} ->
            index(collection)
          error ->
            error
        end
      %{"type" => @bibliography_type_key} = core_fields ->
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
