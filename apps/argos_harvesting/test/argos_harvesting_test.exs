defmodule ArgosHarvestingTest do
  use ExUnit.Case
  doctest ArgosHarvesting.Application

  alias ArgosHarvesting.{
    Gazetteer,
    Thesauri,
    Bibliography
  }

  alias ArgosHarvesting.TestHelpers

  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "gazetteer harvester harvests by date" do
      result =
        Date.utc_today()
        |> Date.add(-7)
        |> Gazetteer.run_harvest()

      assert :ok = result
    end

    test "thesauri harvester harvests by date" do
      result =
        Date.utc_today()
        |> Date.add(-7)
        |> Thesauri.run_harvest()

      assert :ok = result
    end

    test "bibliography harvester harvests by date" do
      result =
        DateTime.now!("Etc/UTC")
        |> Bibliography.run_harvest()

      assert [] = result
    end
  end
end
