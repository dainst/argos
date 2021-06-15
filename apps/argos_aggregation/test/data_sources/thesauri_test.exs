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
    id = "_b7707545"

    {:ok, concept} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> Concept.create()

    assert %Concept{core_fields: %CoreFields{source_id: ^id}} = concept
  end

  @tag timeout: :infinity
  test "get all yields list of concepts" do
    records =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10
    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %Concept{}} = Concept.create(record)
    end)
  end

  test "get by date yields concept as result" do
    records  =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %Concept{}} = Concept.create(record)
    end)
  end

  test "get by tomorrow yields empty list" do
    records  =
      Date.utc_today()
      |> Date.add(1)
      |> DataProvider.get_by_date()
      |> Enum.to_list()

    assert Enum.count(records) == 0

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
