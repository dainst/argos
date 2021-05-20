defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, Bibliography
  }

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  def index(%{_id: id, _source: doc}) do
    payload =
      %{
        doc: doc
      }
      |> Poison.encode!

    Finch.build(
      :post,
      "#{@base_url}/_update/#{id}",
      @headers,
      payload
    )
    |> Finch.request(ArgosFinch)
    |> parse_response()
  end

  def index(%Thesauri.Concept{} = concept) do
    %{
        doc: Map.put(concept, :type, :concept),
        doc_as_upsert: true
    }
    |> index(concept)
  end

  def index(%Gazetteer.Place{} = place) do
    %{
        doc: Map.put(place, :type, :place),
        doc_as_upsert: true
    }
    |> index(place)
  end

  def index(%Chronontology.TemporalConcept{} = temporal_concept) do
    %{
        doc: Map.put(temporal_concept, :type, :temporal_concept),
        doc_as_upsert: true
    }
    |> index(temporal_concept)
  end

  def index(%Project.Project{} = project) do
      %{
        doc: Map.put(project, :type, :project),
        doc_as_upsert: true
      }
      |> index(project)
  end

  def index(%Bibliography.BibliographicRecord{} = record) do
    %{
      doc: Map.put(record, :type, :bibliography),
      doc_as_upsert: true
    }
    |> index(record)
  end

  defp index(payload, argos_struct) do
    res =
      payload
      |> upsert()
      |> parse_response()

    res_reference_update =
      res
      |> check_update(argos_struct)

    %{upsert_response: res, reference_update_response: res_reference_update}
  end

  def upsert(%{doc: %{type: type, id: id}} = data) do
    Logger.debug("Indexing #{type}-#{id}.")

    data_json =
      data
      |> Poison.encode!

    Finch.build(
      :post,
      "#{@base_url}/_update/#{type}-#{id}",
      @headers,
      data_json
    )
    |> Finch.request(ArgosFinch)
  end

  defp parse_response({:ok, %Finch.Response{body: body}}) do
    Poison.decode!(body)
  end

  defp get_search_hits(%{"hits" => %{"hits" => hits}}) do
    hits
  end


  @doc """
  checks the result of the last action
  returns {:ok, "created"} or {:ok, "noop"} in those case
  in case of an update {:ok, "subdocs_updated"} or {:ok, "no_subdocuments"}
  """
  defp check_update(%{"result" => "updated"}, updated_content) do
    Logger.info("Apply Update")

    search_referencing_docs(updated_content)
    |> parse_response()
    |> get_search_hits()
    |> Enum.map(&update_reference(&1, updated_content))
    |> Enum.map(&index/1)
  end
  defp check_update(%{"result" => "created"}, _obj) do
    []
  end
  defp check_update(%{"result" => "noop"} , _obj) do
    []
  end
  defp check_update(_res, _obj) do
    {:error, "error in create/update process"}
  end

  defp search_referencing_docs(%Gazetteer.Place{} = place) do
    search_for_subdocument(:spatial, place.id)
  end
  defp search_referencing_docs(%Chronontology.TemporalConcept{} = temporal) do
    search_for_subdocument(:temporal, temporal.id)
  end
  defp search_referencing_docs(%Thesauri.Concept{} = concept) do
    search_for_subdocument(:subject, concept.id)
  end
  defp search_referencing_docs(_unknown_obj) do
    []
  end

  def search_for_subdocument(doc_type, doc_id) do
    query = Poison.encode!(%{
      query: %{
        query_string: %{
          query: "#{doc_id}",
            fields: ["#{doc_type}.resource.id"]
          }
        }
      }
    )
    Finch.build(:post, "#{@base_url}/_search", @headers, query)
    |> Finch.request(ArgosFinch)
  end

  defp update_reference(%{"_id" => id, "_source" => parent }, %Gazetteer.Place{} = place) do
    %{
      _id: id,
      _source: put_in(parent, ["spatial", Access.filter(&(&1["resource"]["id"] == place.id)), "resource"], place )
    }
  end
  defp update_reference(%{"_id" => id, "_source" => parent}, %Chronontology.TemporalConcept{} = temporal) do
    %{
      _id: id,
      _source: put_in(parent, ["temporal", Access.filter(&(&1["resource"]["id"] == temporal.id)), "resource"], temporal )
    }
  end
  defp update_reference(%{"_id" => id, "_source" => parent}, %Thesauri.Concept{} = subject) do
    %{
      _id: id,
      _source: put_in(parent, ["subject", Access.filter(&(&1["resource"]["id"] == subject.id)), "resource"], subject )
    }
  end
end
