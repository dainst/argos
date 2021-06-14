defmodule ArgosAggregation.ThesauriTest do
  use ExUnit.Case

  require Logger

  doctest ArgosAggregation.Thesauri

  alias ArgosAggregation.Thesauri.{
    Concept,
    DataProvider
  }

  alias ArgosAggregation.CoreFields
  alias ArgosAggregation.TestHelpers

  test "get by id yields concept with requested id" do
    id = "_b7707545"

    {:ok, concept} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> Concept.create()

    assert %Concept{core_fields: %CoreFields{source_id: ^id}} = concept
  end

  test "get by id with invalid id yields 404" do
    invalid_id = "i-am-non-existant"

    error = DataProvider.get_by_id(invalid_id)

    expected_error = {
      :error,
      "Received unhandled status code 404 for http://thesauri.dainst.org/#{invalid_id}.rdf."
    }
    assert expected_error == error
  end


  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "concept can be added to index" do
      {:ok, concept} = DataProvider.get_by_id("_b7707545")

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(concept)

      assert %{
        upsert_response: %{"_id" => "concept__b7707545", "result" => "created"}
      } = indexing_response
    end

    test "concept can be reloaded locally" do
      id = "_b7707545"

      # First, load from gazetteer, manually add another title variant and push to index.
      DataProvider.get_by_id(id)
      |> case do
        {:ok, params} -> params
      end
      |> Map.update!(
          "core_fields",
          fn (old_core) ->
            Map.update!(
              old_core,
              "title",
              fn (old_title) ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end)
          end)
      |> ArgosAggregation.ElasticSearch.Indexer.index()

      # Now reload both locally and from iDAI.gazetteer.
      {:ok, concept_from_index} =
        id
        |> DataProvider.get_by_id(false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()
      {:ok, concept_from_gazetteer} =
        id
        |> DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      # Finally compare the title field length.
      assert length(concept_from_index.core_fields.title) - 1 == length(concept_from_gazetteer.core_fields.title)
    end

    test "if concept was requested to be loaded locally, but was missing in the index, it is also automatically indexed" do
      {:ok, concept } =
        DataProvider.get_by_id("_b7707545", false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      TestHelpers.refresh_index()

      assert {:ok, _concept_from_index} = ArgosAggregation.ElasticSearch.DataProvider.get_doc(concept.core_fields.id)
    end
  end

end
