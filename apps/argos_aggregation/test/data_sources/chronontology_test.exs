defmodule ArgosAggregation.ChronontologyTest do
  use ExUnit.Case
  require Logger

  doctest ArgosAggregation.Chronontology

  alias ArgosAggregation.Chronontology.{
    TemporalConcept,
    DataProvider
  }

  alias ArgosAggregation.CoreFields

  alias ArgosAggregation.TestHelpers

  test "get by id yields temporal concept with requested id" do
    id = "X5lOSI8YQFiL"

    assert %TemporalConcept{core_fields: %CoreFields{source_id: id}} = DataProvider.get_by_id(id)
  end

  test "get by id with invalid id yields 404" do
    id = "i-am-non-existant"

    expected_result = {:error, "Received unhandled status code 404 for https://chronontology.dainst.org/data/period/#{id}."}

    assert expected_result == DataProvider.get_by_id(id)
  end
end
