defmodule ArgosHarvestingTest do
  use ExUnit.Case
  doctest ArgosHarvesting.BaseHarvester

  alias ArgosHarvesting.{
    Gazetteer,
    Thesauri,
    Bibliography,
    Chronontology,
    Collection
  }

  @timezone "Etc/UTC"

  @tag timeout: (1000 * 60 * 5)
  # This test may take some time because a lot of "deleted" records are skipped
  # while searching OAI PMH for existing records.
  test "bibliography harvester generalises for base harvester module" do
    ensure_generalisability(Bibliography)
  end

  test "chronontology harvester generalises for base harvester module" do
    ensure_generalisability(Chronontology)
  end

  test "collection harvester generalises for base harvester module" do
    ensure_generalisability(Collection)
  end

  test "gazetteer harvester generalises for base harvester module" do
    ensure_generalisability(Gazetteer)
  end

  test "thesauri harvester generalises for base harvester module" do
    ensure_generalisability(Thesauri)
  end

  defp ensure_generalisability(harvester) do
    result =
      harvester.run_harvest(%{})
      |> Enum.take(10)

    assert is_list(result)
    assert Enum.count(result) == 10

    datetime =
      DateTime.now!(@timezone)
      |> DateTime.add(-60 * 24 * 3)

    result =
      harvester.run_harvest(%{last_run: datetime})
      |> Enum.take(1)

    assert is_list(result)
    assert Enum.count(result) == 0 or Enum.count(result) == 1
  end
end
