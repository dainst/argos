defmodule ArgosAggregation.ElasticSearchIndexer do
  require Logger
  alias ArgosAggregation.{
    Chronontology, Gazetteer, Thesauri, Project, Bibliography
  }

  @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"
  @headers [{"Content-Type", "application/json"}]

  @type_to_struct_mapping [
    {:project, Project.Project.__struct__},
    {:bibliographic_record, Bibliography.BibliographicRecord.__struct__},
    {:concept, Thesauri.Concept.__struct__},
    {:place, Gazetteer.Place.__struct__}
  ]

  def index(argos_struct) do
    {type, _struct} =
      @type_to_struct_mapping
      |> Enum.filter(fn ({_atom, struct}) ->
        # Kein Plan wieso noch einmal struct.__struct__ nötig ist, obwohl es oben bereits mit __struct__ definiert ist.
        struct.__struct__ == argos_struct.__struct__
      end)
      |> List.first()

    res =
      %{
        doc: Map.put(argos_struct, :type, type),
        doc_as_upsert: true
      }
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
  defp check_update(%{"result" => "updated"} = _status, updated_content) do
    Logger.debug("Apply Update")

    case search_referencing_docs(updated_content) do
      :reference_search_not_implemented ->
        #Logger.debug("Reference search not implemented for #{updated_content.__struct__}.")
        []
      res ->
        res
        |> parse_response()
        |> get_search_hits()
        |> Enum.map(&update_reference(&1, updated_content))
        |> Enum.map(&map_to_struct/1)
        |> Enum.map(&index/1)
    end
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
    :reference_search_not_implemented
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

  defp update_reference(%{"_source" => parent }, %Gazetteer.Place{} = place) do
    put_in(parent, ["spatial", Access.filter(&(&1["resource"]["id"] == place.id)), "resource"], Poison.encode!(place) |> Poison.decode!() )
  end
  defp update_reference(%{"_source" => parent}, %Chronontology.TemporalConcept{} = temporal) do
    put_in(parent, ["temporal", Access.filter(&(&1["resource"]["id"] == temporal.id)), "resource"], Poison.encode!(temporal) |> Poison.decode())
  end
  defp update_reference(%{"_source" => parent}, %Thesauri.Concept{} = subject) do
    put_in(parent, ["subject", Access.filter(&(&1["resource"]["id"] == subject.id)), "resource"], Poison.encode!(subject) |> Poison.decode!() )
  end

  defp map_to_struct(map) do
    type =
      map["type"]
      |> String.to_existing_atom()

    {_, struct} =
      @type_to_struct_mapping
      |> Enum.filter(fn {t, _} ->
        t == type
      end)
      |> List.first()

    struct.__struct__.from_map(map)
  end
end
