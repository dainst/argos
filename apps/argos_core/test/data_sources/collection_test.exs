defmodule ArgosCore.CollectionTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosCore.Collection)

  alias ArgosCore.{
    Gazetteer,
    Thesauri,
    Chronontology,
    Collection,
    ElasticSearch.Indexer,
    TestHelpers,
    CoreFields
  }

  @example_json Application.app_dir(:argos_core, "priv/example_collection_params.json")

  test "get by id using an a non existing id 404" do
    {:error, %{status: 404}} = Collection.DataProvider.get_by_id("-1")
  end

  test "get by id using invalid id yields 400" do
    {:error, %{status: 400}} = Collection.DataProvider.get_by_id("not-a-number")
  end

  describe "elastic search tests" do
    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)

      :ok
    end

    test "get by id yields collection" do
      id = "1"

      {:ok, record} =
        id
        |> Collection.DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Collection.Collection.create()

      assert %Collection.Collection{core_fields: %CoreFields{source_id: ^id}} = record
    end

    test "get all yields collections as result" do
      records =
        Collection.DataProvider.get_all()
        |> Enum.take(10)

      assert Enum.count(records) == 10

      records
      |> Enum.each(fn {:ok, record} ->
        assert {:ok, %Collection.Collection{}} = Collection.Collection.create(record)
      end)
    end

    test "collection record's core_fields contains full_record data" do
      id = 1

      {:ok, %{core_fields: %{full_record: %{"id" => record_id}}}} =
        id
        |> Collection.DataProvider.get_by_id()
        |> case do
          {:ok, data} ->
            data
        end
        |> Collection.Collection.create()

      assert record_id == id
    end

    test "updating referenced thesauri concept updates collection" do
      {:ok, ths_data} = Thesauri.DataProvider.get_by_id("_ab3a94b2")

      ths_indexing = Indexer.index(ths_data)

      {:ok, %{"result" => "created"}} = ths_indexing.upsert_response

      collection_indexing =
        with {:ok, file_content} <- File.read(@example_json) do
          {:ok, data} = Poison.decode(file_content)

          data
          |> Collection.CollectionParser.parse_collection()
          |> case do
            {:ok, collection} -> collection
          end
          |> Indexer.index()
        end

      {:ok, %{"result" => "created"}} = collection_indexing.upsert_response

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      ths_indexing =
        ths_data
        |> Map.update!(
          "core_fields",
          fn old_core ->
            Map.update!(
              old_core,
              "title",
              fn old_title ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end
            )
          end
        )
        |> Indexer.index()

      {:ok, %{"result" => "updated"}} = ths_indexing.upsert_response

      %{upsert_response: {:ok, %{"_version" => collection_new_version, "_id" => collection_new_id}}} =
        ths_indexing.referencing_docs_update_response
        |> List.first()

      {:ok, %{"_version" => collection_old_version, "_id" => collection_old_id}} =
        collection_indexing.upsert_response

      assert collection_old_version + 1 == collection_new_version
      assert collection_new_id == collection_old_id
    end

    test "updating referenced gazetteer place updates bibliographic record" do
      {:ok, gaz_data} = Gazetteer.DataProvider.get_by_id("2072406")

      gaz_indexing = Indexer.index(gaz_data)

      {:ok, %{"result" => "created"}} = gaz_indexing.upsert_response

      collection_indexing =
        with {:ok, file_content} <- File.read(@example_json) do
          {:ok, data} = Poison.decode(file_content)

          data
          |> Collection.CollectionParser.parse_collection()
          |> case do
            {:ok, collection} -> collection
          end
          |> Indexer.index()
        end

      {:ok, %{"result" => "created"}} = collection_indexing.upsert_response

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      gaz_indexing =
        gaz_data
        |> Map.update!(
          "core_fields",
          fn old_core ->
            Map.update!(
              old_core,
              "title",
              fn old_title ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end
            )
          end
        )
        |> Indexer.index()

      {:ok, %{"result" => "updated"}} = gaz_indexing.upsert_response

      %{upsert_response: {:ok, %{"_version" => collection_new_version, "_id" => collection_new_id}}} =
        gaz_indexing.referencing_docs_update_response
        |> List.first()

      {:ok, %{"_version" => collection_old_version, "_id" => collection_old_id}} =
        collection_indexing.upsert_response

      assert collection_old_version + 1 == collection_new_version
      assert collection_new_id == collection_old_id
    end

    test "updating referenced chronontology data updates bibliographic record" do
      {:ok, chron_data} = Chronontology.DataProvider.get_by_id("mSrGeypeMHjw")

      chron_indexing = Indexer.index(chron_data)

      {:ok, %{"result" => "created"}} = chron_indexing.upsert_response

      collection_indexing =
        with {:ok, file_content} <- File.read(@example_json) do
          {:ok, data} = Poison.decode(file_content)

          data
          |> Collection.CollectionParser.parse_collection()
          |> case do
            {:ok, collection} -> collection
          end
          |> Indexer.index()
        end

      {:ok, %{"result" => "created"}} = collection_indexing.upsert_response

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      chron_indexing =
        chron_data
        |> Map.update!(
          "core_fields",
          fn old_core ->
            Map.update!(
              old_core,
              "title",
              fn old_title ->
                old_title ++ [%{"text" => "Test name", "lang" => "de"}]
              end
            )
          end
        )
        |> Indexer.index()

      {:ok, %{"result" => "updated"}} = chron_indexing.upsert_response

      %{upsert_response: {:ok, %{"_version" => collection_new_version, "_id" => collection_new_id}}} =
        chron_indexing.referencing_docs_update_response
        |> List.first()

      {:ok, %{"_version" => collection_old_version, "_id" => collection_old_id}} =
        collection_indexing.upsert_response

      assert collection_old_version + 1 == collection_new_version
      assert collection_new_id == collection_old_id
    end
  end
end
