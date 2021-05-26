defmodule ArgosAggregation.GazetteerTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Gazetteer

  alias Helpers.ElasticTestClient, as: TestClient
  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Gazetteer.DataProvider
  alias ArgosAggregation.Gazetteer.Harvester

  test "run gazzetteer data provider get_by_date" do
    [data|_] =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.to_list()
    assert %Place{} = data
  end

  test "run gazzetteer data provider get_by_datetime" do
    [data|_] =
      DataProvider.get_by_date(~U[2021-01-01 19:59:03Z])
      |> Enum.to_list()
    assert %Place{} = data
  end

  test "run gazetteer data provider get_by_id" do
    data = DataProvider.get_by_id("2048575")
    assert {:ok, %Place{}} = data
  end

  test "run gazetteer data provider get_all" do
    [data|_] =
      DataProvider.get_all()
      |> Enum.take(10)
    assert %Place{} = data
  end
end
