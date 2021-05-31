defmodule ArgosAggregation.ThesauriTest do
  use ExUnit.Case

  require Logger

  doctest ArgosAggregation.Thesauri

  alias ArgosAggregation.Thesauri.{
    Concept,
    DataProvider
  }

  alias ArgosAggregation.CoreFields

  test "get by id yields concept with requested id" do
    concept = DataProvider.get_by_id("_b7707545")
    assert %Concept{core_fields: %CoreFields{source_id: "_b7707545"}} = concept
  end

  test "get by id with invalid id yields 404" do
    invalid_id = "i-am-non-existant"

    error = DataProvider.get_by_id(invalid_id)

    expected_error = {
      :error,
      "Received unhandled status code 404 for http://thesauri.dainst.org/#{invalid_id}.rdf."
    }
    assert expected_error == error
  end
end
