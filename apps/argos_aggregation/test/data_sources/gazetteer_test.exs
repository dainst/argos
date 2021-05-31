defmodule ArgosAggregation.GazetteerTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Gazetteer

  alias ArgosAggregation.Gazetteer.{
    Place, DataProvider, Place
  }

  alias ArgosAggregation.CoreFields

  alias ArgosAggregation.TestHelpers

  test "get by id yields place with requested id" do
    assert %Place{ core_fields: %CoreFields{source_id: "2048575"}} = DataProvider.get_by_id("2048575")
  end

  test "get all yields places as result" do
    records =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn(record) ->
      assert %Place{} = record
    end)
  end

  test "get by date yields places as result" do
    records  =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn(record) ->
      assert %Place{} = record
    end)
  end

  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "place can be added to index" do
      place = DataProvider.get_by_id("2048575")

      indexing_response = ArgosAggregation.ElasticSearchIndexer.index(place)

      assert %{
        upsert_response: %{"_id" => "place-2048575", "result" => "created"}
      } = indexing_response
    end
  end
end
