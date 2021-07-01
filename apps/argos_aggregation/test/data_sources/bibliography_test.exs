defmodule ArgosAggregation.BibliographyTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosAggregation.Bibliography)

  alias ArgosAggregation.{
    Gazetteer, Thesauri, Bibliography, Bibliography.BibliographicRecord, ElasticSearch.Indexer, CoreFields, TestHelpers
  }

  @example_json "../../priv/example_zenon_params.json"

  test "get by id with invalid id yields error" do
    assert {:error, "record not-existing not found."} == Bibliography.DataProvider.get_by_id("not-existing")
  end


  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "get all yields bibliographic records as result" do
      records =
        Bibliography.DataProvider.get_all()
        |> Enum.take(10)

      assert Enum.count(records) == 10

      records
      |> Enum.each(fn({:ok, record}) ->
        assert {:ok, %BibliographicRecord{}} = BibliographicRecord.create(record)
      end)
    end

    test "get by id yields bibliographic record" do
      id = "002023378"

      {:ok, record } =
        id
        |> Bibliography.DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Bibliography.BibliographicRecord.create()

        assert %Bibliography.BibliographicRecord{ core_fields: %CoreFields{source_id: ^id}} = record
    end

    test "updating referenced thesauri concept updates bibliographic record" do

      {:ok, ths_data} = Thesauri.DataProvider.get_by_id("_031c59e9")

      ths_indexing = Indexer.index(ths_data)

      assert("created" == ths_indexing.upsert_response["result"])


      biblio_indexing = with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
          |> Bibliography.BibliographyParser.parse_record()
          |> case do
            {:ok, params} -> params
          end
          |> Indexer.index()
      end
      assert("created" == biblio_indexing.upsert_response["result"])

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      ths_indexing =
        ths_data
        |> Map.update!(
          "core_fields",
          fn (old_core) ->
            Map.update!(
              old_core,
              "title",
              fn (old_title) ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end)
          end)
        |> Indexer.index()

      assert("updated" == ths_indexing.upsert_response["result"])

      %{upsert_response: %{"_version" => biblio_new_version, "_id" => biblio_new_id}} =
        ths_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => biblio_old_version, "_id" => biblio_old_id} = biblio_indexing.upsert_response

      assert biblio_old_version + 1 == biblio_new_version
      assert biblio_new_id == biblio_old_id
    end


    test "updating referenced gazetteer place updates bibliographic record" do
      {:ok, gaz_data} = Gazetteer.DataProvider.get_by_id("2338718")

      gaz_indexing = Indexer.index(gaz_data)

      assert("created" == gaz_indexing.upsert_response["result"])
      biblio_indexing = with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
          |> Bibliography.BibliographyParser.parse_record()
          |> case do
            {:ok, params} -> params
          end
          |> Indexer.index()
      end

      assert("created" == biblio_indexing.upsert_response["result"])

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      gaz_indexing =
        gaz_data
        |> Map.update!(
          "core_fields",
          fn (old_core) ->
            Map.update!(
              old_core,
              "title",
              fn (old_title) ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end)
          end)
        |> Indexer.index()

      assert("updated" == gaz_indexing.upsert_response["result"])

      %{upsert_response: %{"_version" => biblio_new_version, "_id" => biblio_new_id}} =
        gaz_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => biblio_old_version, "_id" => biblio_old_id} = biblio_indexing.upsert_response

      assert biblio_old_version + 1 == biblio_new_version
      assert biblio_new_id == biblio_old_id
    end
  end

end
