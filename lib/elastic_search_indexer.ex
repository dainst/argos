defmodule ElasticSearchIndexer do
  alias Argos.Data.{
    Thesauri
  }

  @headers [{"Content-Type", "application/json"}]

  @base_url Application.get_env(:argos, :elasticsearch_url)

  def index(%Thesauri.Concept{} = thesauri_concept) do
    payload =
      %{
        doc: thesauri_concept,
        doc_as_upsert: true
      }
      |> Poison.encode!()
    id = thesauri_concept.uri

    upsert(payload, id)
    |> unwrap_response!()
  end

  # def index(%Gazetteer.Place{} = gazetteer_concept) do
  #   # TODO
  # end

  defp upsert(data, id) do
    HTTPoison.post!(
      "#{@base_url}/_update/#{id}",
      data,
      @headers
    )
  end

  defp unwrap_response!(%HTTPoison.Response{body: body}) do
    result = Poison.decode!(body)
    if Map.has_key?(result, "error") do
      raise result["error"]
    end
    result
  end

end
