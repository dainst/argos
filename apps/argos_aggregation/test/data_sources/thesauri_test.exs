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
  alias ArgosAggregation.TestHelpers


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

  describe "dataprovider tests" do
    test "get by id but get an empty return" do
      id = "_b7707545"

      assert {:error, "Malformed xml document"} = DataProvider.get_by_id(id, true, %{remote: DataSourceClient.TestEmptyReturns})
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

  describe "elastic search integration tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "concept can be added to index" do
      {:ok, concept} = DataProvider.get_by_id("_b7707545")

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(concept)

      assert %{
        upsert_response: %{"_id" => "concept__b7707545", "result" => "created"}
      } = indexing_response
    end

    test "concept can be reloaded locally" do
      id = "_b7707545"

      # First, load from concept, manually add another label variant and push to index.
      case DataProvider.get_by_id(id) do
        {:ok, params} ->
          params
          |> Map.update!(
            "core_fields",
            fn (old_core) ->
              Map.update!(
                old_core,
                "title",
                fn (old_title) ->
                  old_title ++ [%{"text" => "Test name", "lang" => "mz"}]
                end)
            end)
          |> ArgosAggregation.ElasticSearch.Indexer.index()
      end


      # Now reload both locally and from iDAI.gazetteer.
      {:ok, concept_from_index} =
        id
        |> DataProvider.get_by_id(false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()
      {:ok, concept_from_thesaurus} =
        id
        |> DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      # Finally compare the title field length.
      assert length(concept_from_index.core_fields.title) - 1 == length(concept_from_thesaurus.core_fields.title)
    end

    test "if concept was requested to be loaded locally, but was missing in the index, it is also automatically indexed" do
      {:ok, concept } =
        DataProvider.get_by_id("_8bca4bf1", false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      TestHelpers.refresh_index()

      assert {:ok, _concept_from_index} = ArgosAggregation.ElasticSearch.DataProvider.get_doc(concept.core_fields.id)
    end
  end
end
