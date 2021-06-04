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

  @example_project_params %{
    "descriptions" => [
      %{"content" => "Eine sehr informative Projektbeschreibung.", "language_code" => "de"},
      %{"content" => "This is a very informativ project description.", "language_code" => "en"}
    ],
    "ends_at" => "2023-10-10",
    "external_links" => [
      %{
        "labels" => [
          %{
            "content" => "Super link, Background Story, wie alles begann!",
            "language_code" => "de"
          },
          %{
            "content" => "The prequel to the main story, with a sick hook!",
            "language_code" => "en"
          }
        ],
        "url" =>
          "https://antikewelt.de/2021/01/15/wieder-intakt-die-restaurierung-der-saeulen-der-casa-del-fauno-in-pompeji/"
      }
    ],
    "id" => 1,
    "images" => [
      %{
        "labels" => [
          %{"content" => "Voll das passende Bild.", "language_code" => "de"},
          %{"content" => "Just a very fitting picture.", "language_code" => "en"}
        ],
        "path" => "http://localhost:4000/media/projects/1/idai_archive_spanish_codices.jpg",
        "primary" => true
      }
    ],
    "inserted_at" => "2021-06-01T07:44:07",
    "linked_resources" => [
      %{
        "descriptions" => [
          %{"content" => "Der Ort über den geschrieben wird.", "language_code" => "de"},
          %{"content" => "The place written about.", "language_code" => "en"}
        ],
        "labels" => [
          %{"content" => "Rome", "language_code" => "en"},
          %{"content" => "Rom", "language_code" => "de"}
        ],
        "linked_system" => "gazetteer",
        "res_id" => "2323295",
        "uri" => "https://gazetteer.dainst.org/place/2323295"
      },
      %{
        "descriptions" => [
          %{"content" => "Der Ort über den auch geschrieben wird.", "language_code" => "de"},
          %{"content" => "The place also written about.", "language_code" => "en"}
        ],
        "labels" => [
          %{"content" => "Etruria", "language_code" => "en"},
          %{"content" => "Etrurien", "language_code" => "de"}
        ],
        "linked_system" => "gazetteer",
        "res_id" => "2072406",
        "uri" => "https://gazetteer.dainst.org/place/2072406"
      },
      %{
        "descriptions" => [
          %{"content" => "Der Zeit über die geschrieben wird.", "language_code" => "de"},
          %{"content" => "The period written about.", "language_code" => "en"}
        ],
        "labels" => [
          %{"content" => "Classic", "language_code" => "en"},
          %{"content" => "Klassik", "language_code" => "de"}
        ],
        "linked_system" => "chronontology",
        "res_id" => "mSrGeypeMHjw",
        "uri" => "https://chronontology.dainst.org/period/mSrGeypeMHjw"
      },
      %{
        "descriptions" => [],
        "labels" => [],
        "linked_system" => "thesaurus",
        "res_id" => "_ab3a94b2",
        "uri" => "http://thesauri.dainst.org/_ab3a94b2"
      },
      %{
        "descriptions" => [],
        "labels" => [],
        "linked_system" => "arachne",
        "res_id" => "1140385",
        "uri" => "http://arachne.dainst.org/entity/1140385"
      }
    ],
    "project_key" => "SPP2143",
    "stakeholders" => [
      %{
        "person" => %{
          "first_name" => "Benjamin",
          "last_name" => "Ducke",
          "orc_id" => "https://orcid.org/0000-0002-0560-4749",
          "title" => "Dr."
        },
        "role" => "manager"
      },
      %{
        "person" => %{
          "first_name" => "Marcel",
          "last_name" => "Riedel",
          "orc_id" => "https://orcid.org/0000-0002-2701-9356",
          "title" => ""
        },
        "role" => "intern"
      }
    ],
    "starts_at" => "2019-01-10",
    "titles" => [
      %{"content" => "Großartiges Ausgrabungsprojekt", "language_code" => "de"},
      %{"content" => "Great digging project", "language_code" => "en"}
    ],
    "updated_at" => "2021-06-01T07:44:07"
  }

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

      project_indexing =
        @example_project_params
        |> Project.ProjectParser.parse_project()
        |> case do
          {:ok, project} -> project
        end
        |> Indexer.index()

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

      project_indexing =
        @example_project_params
        |> Project.ProjectParser.parse_project()|> case do
          {:ok, project} -> project
        end
        |> Indexer.index()

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

      project_indexing =
        @example_project_params
        |> Project.ProjectParser.parse_project()
        |> case do
          {:ok, project} -> project
        end
        |> Indexer.index()

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
