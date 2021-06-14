defmodule ArgosAPITest do
  use ExUnit.Case, async: true
  use Plug.Test
  doctest ArgosAPI

  alias ArgosAPI.{
    TestHelpers
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

  test "invalid size yields 400 status" do
    response =
      conn(:get, "/search", %{size: "invalid"})
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?size=-1")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?size=10.5")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400
  end

  test "invalid from yields 400 status" do
    response =
      conn(:get, "/search?from=invalid")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?from=-1")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400

    response =
      conn(:get, "/search?from=10.5")
      |> ArgosAPI.Router.call(%{})

    assert response.status == 400
  end

  test "invalid filters yield 400 status" do
    %{status: status} =
      conn(:get, "/search?filter[]=missing_colon")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

    %{status: status} =
      conn(:get, "/search?!filter[]=missing_colon")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

    %{status: status} =
      conn(:get, "/search?filter=missing_brackets")
      |> ArgosAPI.Router.call(%{})

    assert status == 400

  end

  describe "elastic search tests" do

    setup do
      TestHelpers.create_index()

      @example_project_params
      |> ArgosAggregation.Project.ProjectParser.parse_project()
      |> case do
        {:ok, params} -> params
      end
      |> ArgosAggregation.ElasticSearch.Indexer.index()

      TestHelpers.refresh_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "basic search yields result" do
      %{resp_body: body } =
        conn(:get, "/search?q=*")
        |> ArgosAPI.Router.call(%{})

      %{"total" => total} =
        body
        |> Poison.decode!()

      # 1 project, 2 places, 1 concept
      assert total == 4
    end

    test "document is accessable through endpoint" do
      %{resp_body: body } =
        conn(:get, "/doc/project_1")
        |> ArgosAPI.Router.call(%{})

      assert %{"core_fields" => %{"id" => "project_1" }} = Poison.decode!(body)
    end

    test "invalid document id yields 404" do
      %{status: status } =
        conn(:get, "/doc/non_existing")
        |> ArgosAPI.Router.call(%{})

      assert status == 404
    end
  end
end
