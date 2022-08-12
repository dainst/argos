defmodule ArgosCore.GeoserverTest do
  use ExUnit.Case
  require Logger

  doctest ArgosCore.Geoserver

  alias ArgosCore.Geoserver.{
    MapDocument,
    DataProvider
  }

  alias ArgosCore.CoreFields

  alias ArgosCore.TestHelpers

  test "get by id yields map with requested id" do
    id = "5459"

    {:ok, map_document} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> MapDocument.create()

    assert %MapDocument{core_fields: %CoreFields{source_id: ^id}} = map_document
  end

  test "get by id with unknown id yields 404 error" do
    {:error, %{status: 404}} = DataProvider.get_by_id("non-existant")
  end

  test "get all yields map as result" do
    doc_params =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(doc_params) == 10

    doc_params
    |> Enum.each(fn {:ok, doc_params} ->
      assert {:ok, %MapDocument{}} = MapDocument.create(doc_params)
    end)
  end

  describe "elastic search integration tests" do
    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)

      :ok
    end

    test "map documents can be added to index" do
      {:ok, map_document} = DataProvider.get_by_id("5459")

      indexing_response = ArgosCore.ElasticSearch.Indexer.index(map_document)

      %{
        upsert_response: {:ok, %{"_id" => "map_5459", "result" => "created"}}
      } = indexing_response
    end
  end
end
