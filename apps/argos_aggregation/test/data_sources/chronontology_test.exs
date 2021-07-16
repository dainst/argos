defmodule ArgosAggregation.ChronontologyTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Chronontology

  alias ArgosAggregation.Chronontology.{
    TemporalConcept,
    DataProvider
  }

  alias ArgosAggregation.TestHelpers

  alias ArgosAggregation.CoreFields

  test "get by id yields temporal concept with requested id" do
    id = "X5lOSI8YQFiL"

    {:ok, tc} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> TemporalConcept.create()

    assert %TemporalConcept{core_fields: %CoreFields{source_id: ^id}} = tc
  end

  test "get by id with invalid id yields 404" do
    id = "i-am-non-existant"

    expected_result = {:error, "Received unhandled status code 404."}

    assert expected_result == DataProvider.get_by_id(id)
  end

  test "get all yields temporal concepts as result" do
    records =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %TemporalConcept{}} = TemporalConcept.create(record)
    end)
  end

  test "get by date yields temporal concepts as result" do
    records  =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.take(3)

    assert Enum.count(records) == 3

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %TemporalConcept{}} = TemporalConcept.create(record)
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

    test "temporal concept can be added to index" do
      {:ok, temporalConcept} = DataProvider.get_by_id("X5lOSI8YQFiL")

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(temporalConcept)

      assert %{
        upsert_response: %{"_id" => "temporal_concept_X5lOSI8YQFiL", "result" => "created"}
      } = indexing_response
    end
  end
end
