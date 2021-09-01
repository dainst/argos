defmodule ArgosCore.GazetteerTest do
  use ExUnit.Case
  require Logger

  doctest ArgosCore.Gazetteer

  alias ArgosCore.Gazetteer.{
    Place, DataProvider
  }

  alias ArgosCore.CoreFields

  alias ArgosCore.TestHelpers

  test "get by id yields place with requested id" do
    id = "2048575"

    {:ok, place} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> Place.create()

    assert %Place{ core_fields: %CoreFields{source_id: ^id}} = place
  end

  test "get by id with unknown id yields 404 error" do
    {:error, %{status: 404}} = DataProvider.get_by_id("non-existant")
  end

  test "get all yields places as result" do
    records =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %Place{}} = Place.create(record)
    end)
  end

  test "get by date yields places as result" do
    records  =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.take(10)
    assert Enum.count(records) == 10

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %Place{}} = Place.create(record)
    end)
  end

  test "gazetteer record's core_fields contains full_record data" do
    id = "2048575"

    {:ok, %{core_fields: %{full_record: %{"gazId" => record_id}}}} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, data} ->
          data
      end
      |> Place.create()

    assert record_id == id
  end

  describe "elastic search integration tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "place can be added to index" do
      {:ok, place} = DataProvider.get_by_id("2048575")

      indexing_response = ArgosCore.ElasticSearch.Indexer.index(place)

      %{
        upsert_response: {:ok, %{"_id" => "place_2048575", "result" => "created"}
      }} = indexing_response
    end

    test "place can be reloaded locally" do
      id = "2048575"

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
      |> ArgosCore.ElasticSearch.Indexer.index()

      # Now reload both locally and from iDAI.gazetteer.
      {:ok, place_from_index} =
        id
        |> DataProvider.get_by_id(false)
        |> case do
          {:ok, params} -> params
        end
        |> Place.create()
      {:ok, place_from_gazetteer} =
        id
        |> DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Place.create()

      # Finally compare the title field length.
      assert length(place_from_index.core_fields.title) - 1 == length(place_from_gazetteer.core_fields.title)
    end

    test "if place was requested to be loaded locally, but was missing in the index, it is also automatically indexed" do
      {:ok, place } =
        DataProvider.get_by_id("2048575", false)
        |> case do
          {:ok, params} -> params
        end
        |> Place.create()

      TestHelpers.refresh_index()

      assert {:ok, _place_from_index} = ArgosCore.ElasticSearch.DataProvider.get_doc(place.core_fields.id)
    end
  end
end
