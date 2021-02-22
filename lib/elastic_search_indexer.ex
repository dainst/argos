defmodule Argos.ElasticSearchIndexer do
  require Logger
  alias Argos.Data.{
    Chronontology, Gazetteer, Thesauri, Project
  }

  @headers [{"Content-Type", "application/json"}]

  @base_url Application.get_env(:argos, :elasticsearch_url)

  def index(%Thesauri.Concept{} = concept) do
    payload =
      %{
        doc:
          concept
          |> Map.put(:id, concept.uri)
          |> Map.put(:type, "concept"),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
  end

  def index(%Gazetteer.Place{} = place) do
    payload =
      %{
        doc:
          place
          |> Map.put(:id, place.uri)
          |> Map.put(:type, "place"),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
  end

  def index(%Chronontology.TemporalConcept{} = temporal_concept) do
    payload =
      %{
        doc:
          temporal_concept
          |> Map.put(:id, temporal_concept.uri)
          |> Map.put(:type, "temporal_concept"),
        doc_as_upsert: true
      }

    upsert(payload)
    |> parse_response!()
  end

  def index(%Project.Project{} = project) do
    payload =
      %{
        doc: Map.put(project, :type, "project"),
        doc_as_upsert: true
      }

      upsert(payload)
      |> parse_response!()
  end

  defp upsert(%{doc: %{type: type, id: id}} = data) do
    id_encoded = Base.encode64(id)

    Logger.info("Indexing #{type} #{id} as #{id_encoded}.")

    data_json =
      data
      |> Poison.encode!

    "#{@base_url}/_update/#{id_encoded}"
    |> HTTPoison.post!(
      data_json,
      @headers
    )
  end

  defp parse_response!(%HTTPoison.Response{body: body}) do
    result = Poison.decode!(body)
    if Map.has_key?(result, "error") do
      raise result["error"]
    end
    result
  end

end
