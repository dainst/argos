defmodule ArgosAggregation.ProjectTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosAggregation.Project)

  alias ArgosAggregation.{
    Gazetteer,
    Thesauri,
    Chronontology,
    Project,
    ElasticSearch.Indexer,
    TestHelpers,
    CoreFields
  }
  @example_json "../../priv/example_projects_params.json"

  test "get by id with invalid id yields error" do
    assert {:error, 404} == Project.DataProvider.get_by_id("-1")
    assert {:error, 400} == Project.DataProvider.get_by_id("not-a-number")
  end

  describe "elastic search tests" do
    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

      test "get by id yields project" do
        id = "1"

        {:ok, record} =
          id
          |> Project.DataProvider.get_by_id()
          |> case do
            {:ok, params} -> params
          end
          |> Project.Project.create()

        assert %Project.Project{core_fields: %CoreFields{source_id: ^id}} = record
      end

    test "get all yields projects as result" do
      records =
        Project.DataProvider.get_all()
        |> Enum.take(10)

      assert Enum.count(records) == 10

      records
      |> Enum.each(fn {:ok, record} ->
        assert {:ok, %Project.Project{}} = Project.Project.create(record)
      end)
    end

    test "updating referenced thesauri concept updates project" do
      {:ok, ths_data} = Thesauri.DataProvider.get_by_id("_ab3a94b2")

      ths_indexing = Indexer.index(ths_data)

      assert("created" == ths_indexing.upsert_response["result"])


      project_indexing = with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
          |> Project.ProjectParser.parse_project()|> case do
            {:ok, project} -> project
          end
          |> Indexer.index()
      end

      assert("created" == project_indexing.upsert_response["result"])

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

      %{upsert_response: %{"_version" => project_new_version, "_id" => project_new_id}} =
        ths_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => project_old_version, "_id" => project_old_id} =
        project_indexing.upsert_response

      assert project_old_version + 1 == project_new_version
      assert project_new_id == project_old_id
    end

    test "updating referenced gazetteer place updates bibliographic record" do
      {:ok, gaz_data} = Gazetteer.DataProvider.get_by_id("2072406")

      gaz_indexing = Indexer.index(gaz_data)

      assert("created" == gaz_indexing.upsert_response["result"])
      project_indexing = with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
          |> Project.ProjectParser.parse_project()|> case do
            {:ok, project} -> project
          end
          |> Indexer.index()
      end
      assert("created" == project_indexing.upsert_response["result"])

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

      %{upsert_response: %{"_version" => project_new_version, "_id" => project_new_id}} =
        gaz_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => project_old_version, "_id" => project_old_id} = project_indexing.upsert_response

      assert project_old_version + 1 == project_new_version
      assert project_new_id == project_old_id
    end

    test "updating referenced chronontology data updates bibliographic record" do
      {:ok, chron_data} = Chronontology.DataProvider.get_by_id("mSrGeypeMHjw")

      chron_indexing = Indexer.index(chron_data)

      assert("created" == chron_indexing.upsert_response["result"])

      project_indexing = with {:ok, file_content} <- File.read(@example_json) do
        {:ok,data} = Poison.decode(file_content)
        data
          |> Project.ProjectParser.parse_project()|> case do
            {:ok, project} -> project
          end
          |> Indexer.index()
      end

      assert("created" == project_indexing.upsert_response["result"])

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      chron_indexing =
        chron_data
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

      assert("updated" == chron_indexing.upsert_response["result"])

      %{upsert_response: %{"_version" => project_new_version, "_id" => project_new_id}} =
        chron_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => project_old_version, "_id" => project_old_id} = project_indexing.upsert_response

      assert project_old_version + 1 == project_new_version
      assert project_new_id == project_old_id
    end

  end
end
