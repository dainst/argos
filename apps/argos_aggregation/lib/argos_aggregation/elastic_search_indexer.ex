defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, UpdateController.Observer
  }

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
    |> check_update("thesaurus", concept.id)
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
    |> check_update("gazetteer", place.id)
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
    |> check_update("chronontology", temporal_concept.id)
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

  defp upsert(%{doc: %{type: type, id: id}} = data) do
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

  defp check_update(%{"result" => "updated"}, kind, id) do
    Observer.updated_resource(:update_observer, kind, id)
  end

end
