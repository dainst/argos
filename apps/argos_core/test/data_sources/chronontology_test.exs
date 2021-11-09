defmodule ArgosCore.ChronontologyTest do
  use ExUnit.Case
  require Logger

  doctest ArgosCore.Chronontology

  alias ArgosCore.Chronontology.{
    TemporalConcept,
    DataProvider
  }

  alias ArgosCore.{
    Gazetteer,
    ElasticSearch.Indexer,
    TestHelpers,
    CoreFields
  }

  @example_json Application.app_dir(:argos_core, "priv/example_chronontology_params.json")
  |> File.read!()
  |> Poison.decode!()

  test "get by id yields temporal concept with requested id" do
    id = "X5lOSI8YQFiL"

    {:ok, tc} =
      id
      |> DataProvider.get_by_id()
      |> case do
        {:ok, params} -> params
      end
      |> TemporalConcept.create()

    assert %TemporalConcept{core_fields: %CoreFields{source_id: ^id}} = tc
  end

  test "get by id with invalid id yields 404" do
    id = "i-am-non-existant"

    {:error, %{status: 404}} = DataProvider.get_by_id(id)
  end

  test "get all yields temporal concepts as result" do
    records =
      DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %TemporalConcept{}} = TemporalConcept.create(record)
    end)
  end

  test "get by date yields temporal concepts as result" do
    records  =
      DataProvider.get_by_date(~D[2021-01-01])
      |> Enum.take(3)

    assert Enum.count(records) == 3

    records
    |> Enum.each(fn({:ok, record}) ->
      assert {:ok, %TemporalConcept{}} = TemporalConcept.create(record)
    end)
  end

  test "chronotology record's core_fields contains full_record data" do
    id = "X5lOSI8YQFiL"

    {:ok, %{core_fields: %{full_record: %{"resource" => %{"id" => record_id}}}}} =
      DataProvider.get_by_id(id)
      |> case do
        {:ok, data} ->
          data
         end
      |> TemporalConcept.create()

    assert record_id == id
  end

  test "gazetteer urls in chronontology data get parsed as external link" do
    {:ok, %{core_fields: %{spatial_topics: spatial_topics}}} =
      @example_json
      |> DataProvider.parse_period_data()
      |> case do
        {:ok, params} ->
          params
      end
      |> TemporalConcept.create()

    count =
      Enum.count(
        @example_json["resource"]["spatiallyPartOfRegion"]
      ) + Enum.count(
        @example_json["resource"]["hasCoreArea"]
      )

    # One "haseCoreArea" url in the example is not a gazetteer url, thus expect -1
    assert count - 1 == Enum.count(spatial_topics)
  end


  describe "elastic search interaction |" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "temporal concept can be added to index" do
      {:ok, temporalConcept} = DataProvider.get_by_id("X5lOSI8YQFiL")

      indexing_response = ArgosCore.ElasticSearch.Indexer.index(temporalConcept)

      %{
        upsert_response: {:ok, %{"_id" => "temporal_concept_X5lOSI8YQFiL", "result" => "created"}
      }}  = indexing_response
    end

    test "updating referenced gazetteer place updates temporal concept" do
      {:ok, gaz_data} = Gazetteer.DataProvider.get_by_id("2751681")

      gaz_indexing = Indexer.index(gaz_data)

      {:ok, %{"result" => "created"}} = gaz_indexing.upsert_response

      chrono_indexing =
        @example_json
        |> DataProvider.parse_period_data()
        |> case do
          {:ok, params} -> params
        end
        |> Indexer.index()

      {:ok, %{"result" => "created"}} = chrono_indexing.upsert_response

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

      {:ok, %{"result" => "updated"}} = gaz_indexing.upsert_response

      %{upsert_response: {:ok, %{"_version" => chrono_new_version, "_id" => chrono_new_id}}} =
        gaz_indexing.referencing_docs_update_response
        |> List.first()

      {:ok, %{"_version" => chrono_old_version, "_id" => chrono_old_id}} = chrono_indexing.upsert_response

      assert chrono_old_version + 1 == chrono_new_version
      assert chrono_new_id == chrono_old_id
    end
  end
end
