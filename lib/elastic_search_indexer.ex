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
        doc: concept,
        doc_as_upsert: true
      }
      |> Poison.encode!()

    upsert(payload, concept.uri)
    |> parse_response!()
  end

  def index(%Gazetteer.Place{} = place) do
    payload =
      %{
        doc: place,
        doc_as_upsert: true
      }
      |> Poison.encode!()

    upsert(payload, place.uri)
    |> parse_response!()
  end

  def index(%Chronontology.TemporalConcept{} = temporal_concept) do
    payload =
      %{
        doc: temporal_concept,
        doc_as_upsert: true
      }
      |> Poison.encode!()

    upsert(payload, temporal_concept.uri)
    |> parse_response!()
  end

  def index(%Project.Project{} = project) do
    payload =
      %{
        doc: project,
        doc_as_upsert: true
      }
      |> Poison.encode!
      Logger.info("Upserting project with id #{project.id}")
      upsert(payload, project.id)
      |> parse_response!()
  end

  defp upsert(data, id) do
    "#{@base_url}/_update/#{id}"
    |> HTTPoison.post!(
      data,
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
