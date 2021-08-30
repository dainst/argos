defmodule ArgosCore.BibliographyTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosCore.Bibliography)

  alias ArgosCore.{
    Gazetteer, Thesauri, Bibliography, Bibliography.BibliographicRecord, ElasticSearch.Indexer, CoreFields, TestHelpers
  }

  @example_json Application.app_dir(:argos_core, "priv/example_zenon_params.json")
    |> File.read!()
    |> Poison.decode!()

  test "get by id with invalid id yields error" do
    assert {:error, "record not-existing not found."} == Bibliography.DataProvider.get_by_id("not-existing")
  end

  test "bibliographyic record's core_fields contains full_record data" do
    id = "002023378"

    {:ok, %{core_fields: %{full_record: %{ "id" => record_id}}}} =
      id
      |> Bibliography.DataProvider.get_by_id()
      |> case do
        {:ok, data} ->
          data
         end
      |> BibliographicRecord.create()

    assert record_id == id
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

    test "urls in zenon data get parsed as external link" do
      {:ok, %{core_fields: %{external_links: [%{url: mapped_link_url},%{url: linked_record_url}]}}} =
        @example_json
        |> Bibliography.BibliographyParser.parse_record()
        |> case do
          {:ok, data} ->
            data
        end
        |> BibliographicRecord.create()

      %{"urls" => [%{"url" => input_url}]} = @example_json

      assert input_url == linked_record_url
      assert mapped_link_url == "https://publications.dainst.org/journals/index.php/aa/article/view/2820"
    end

    test "updating referenced thesauri concept updates bibliographic record" do

      {:ok, ths_data} = Thesauri.DataProvider.get_by_id("_031c59e9")

      ths_indexing = Indexer.index(ths_data)

      assert("created" == ths_indexing.upsert_response["result"])


      biblio_indexing =
        @example_json
        |> Bibliography.BibliographyParser.parse_record()
        |> case do
          {:ok, params} -> params
        end
        |> Indexer.index()

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
      biblio_indexing =
        @example_json
        |> Bibliography.BibliographyParser.parse_record()
        |> case do
          {:ok, params} -> params
        end
        |> Indexer.index()

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