defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project
  }

  @headers [{"Content-Type", "application/json"}]

  @base_url Application.get_env(:argos_api, :elasticsearch_url)

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
    if Map.has_key?(result, "error") do
      raise result["error"]
    end
    result
  end

end
