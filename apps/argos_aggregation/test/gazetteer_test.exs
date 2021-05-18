defmodule ArgosAggregation.GazetteerTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Gazetteer

  alias Helpers.ElasticTestClient, as: TestClient
  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Gazetteer.DataProvider
  alias ArgosAggregation.Gazetteer.Harvester

  setup_all %{} do
    Logger.info("starting tests")
    Logger.info("creating test index")
    TestClient.create_test_index()
    TestClient.put_mapping()

    on_exit(fn ->
      Logger.info("delete test index")
      TestClient.delete_test_index()
    end)
    :ok
  end


  test "run gazzetteer data provider get_by_date" do
    [data|_] =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.to_list()
    assert %Place{} = data
  end

  test "run gazetteer data provider get_by_id" do
    data = DataProvider.get_by_id("2048575")
    assert {:ok, %Place{}} = data
  end

  # test "harvest gazetteer by date" do
  #   TestClient.
  #   Harvester.run_harvest(~D[2021-01-01])
  # end


end
