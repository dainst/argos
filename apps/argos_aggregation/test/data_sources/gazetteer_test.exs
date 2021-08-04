defmodule ArgosAggregation.GazetteerTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Gazetteer

  alias ArgosAggregation.Gazetteer.{
    Place, DataProvider, Harvester
  }

  alias ArgosAggregation.CoreFields

  alias ArgosAggregation.TestHelpers

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

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(place)

      assert %{
        upsert_response: %{"_id" => "place_2048575", "result" => "created"}
      } = indexing_response
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
      |> ArgosAggregation.ElasticSearch.Indexer.index()

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

      assert {:ok, _place_from_index} = ArgosAggregation.ElasticSearch.DataProvider.get_doc(place.core_fields.id)
    end

    test "harvester index by date" do
      result =
        Date.utc_today()
        |> Date.add(-7)
        |> Harvester.run_harvest
      assert :ok = result
    end
  end
end
