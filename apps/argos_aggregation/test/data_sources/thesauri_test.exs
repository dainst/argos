defmodule ArgosAggregation.ThesauriTest do
  use ExUnit.Case

  require Logger

  doctest ArgosAggregation.Thesauri

  alias ArgosAggregation.Thesauri.{
    Concept,
    DataProvider,
    DataSourceClient
  }

  alias ArgosAggregation.CoreFields

  defmodule DataSourceClient.TestEmptyReturns do
    @behaviour DataSourceClient

    def read_from_url(_url) do
      {:ok, ""}
    end

    def request_by_date(_date) do
      {:ok, ""}
    end

    def request_node_hierarchy(_id) do
      {:ok, ""}
    end

    def request_root_level() do
      {:ok, ""}
    end

    def request_single_node(_id) do
      {:ok, ""}
    end
  end

  test "get by id but get an empty return" do
    id = "_b7707545"

    assert {:error, "Malformed xml document"} = DataProvider.get_by_id(id, DataSourceClient.TestEmptyReturns)
  end

  test "get by id yields concept with requested id" do
    id = "_b7707545"

    {:ok, concept} =
      with {:ok, params} <- DataProvider.get_by_id(id) do
        params |> Concept.create()
      end

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

  test "get all returning empty string yields error" do
    assert [{:error, "Malformed xml document"}] = DataProvider.get_all(DataSourceClient.TestEmptyReturns) |> Enum.to_list()
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

  test "get by date with returned empty value yields error" do
    assert [{:error, "Malformed xml document"}] =
      DataProvider.get_by_date(~D[2021-01-01], DataSourceClient.TestEmptyReturns) |> Enum.to_list()
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
