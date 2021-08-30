defmodule ArgosHarvestingTest do
  use ExUnit.Case
  doctest ArgosHarvesting.Application

  alias ArgosHarvesting.{
    Gazetteer,
    Thesauri
  }

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
end
