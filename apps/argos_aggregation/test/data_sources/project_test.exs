defmodule ArgosAggregation.ProjectTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosAggregation.Project)

  alias ArgosAggregation.{
    Gazetteer, Thesauri, Project, ElasticSearchIndexer, TranslatedContent, TestHelpers
  }

  @example_project %ArgosAggregation.Project.Project{
    description: [
      %ArgosAggregation.TranslatedContent{
        lang: "en",
        text: "The photo archive at the Berlin head office offers images on vase painting, sculpture, lamps and topography."
      }
    ],
    doi: "",
    end_date: nil,
    external_links: [
      %ArgosAggregation.Project.ExternalLink{
        label: [
          %ArgosAggregation.TranslatedContent{
            lang: "en",
            text: "Berlin head office"
          }
        ],
        role: "data",
        uri: "https://arachne.dainst.org/project/fotoarchivdaiberlin"
      }
    ],
    id: 1,
    images: [
      %ArgosAggregation.Project.Image{
        label: [%ArgosAggregation.TranslatedContent{lang: "en", text: "1"}],
        uri: "http://projects.dainst.org/media/fotoarchivdaiberlin/idai_images_photothek_berlin.jpg"
      }
    ],
    spatial: [
      %{
        label: [],
        resource: %ArgosAggregation.Gazetteer.Place{
          geometry: [
            %{"coordinates" => [13.27303, 52.45491], "type" => "Point"},
            %{
              "coordinates" => [
                [
                  [
                    [13.282808879694812, 52.4424555176076],
                    [13.270105937800281, 52.4424555176076],
                    [13.249849895319812, 52.458043754196396],
                    [13.246588329157703, 52.4601357149835],
                    [13.247274974665515, 52.467665950853025],
                    [13.2546564138745, 52.46599267642029],
                    [13.260836223444812, 52.46735221674203],
                    [13.26238117583739, 52.46672474181137],
                    [13.290018657526844, 52.470907739059676],
                    [13.3095880544995, 52.46745679502749],
                    [13.305639842829578, 52.46536518210906],
                    [13.304094890437, 52.458775951777994],
                    [13.293451885065906, 52.445594532323305],
                    [13.282808879694812, 52.4424555176076]
                  ]
                ]
              ],
              "type" => "MultiPolygon"
            }
          ],
          id: "2048575",
          label: [
            %ArgosAggregation.TranslatedContent{
              lang: "de",
              text: "Berlin- Dahlem"
            },
            %ArgosAggregation.TranslatedContent{lang: "fr", text: "Berlin-Dahlem"},
            %ArgosAggregation.TranslatedContent{lang: "ru", text: "Далем"},
            %ArgosAggregation.TranslatedContent{lang: "de", text: "Berlin-Dahlem"},
            %ArgosAggregation.TranslatedContent{lang: "de", text: "Dahlem"}
          ],
          uri: "https://gazetteer.dainst.org/place/2048575"
        }
      }
    ],
    stakeholders: [],
    start_date: nil,
    subject: [
      %{
        label: [],
        resource: %ArgosAggregation.Thesauri.Concept{
          id: "_328cf29e",
          label: [
            %ArgosAggregation.TranslatedContent{lang: "de", text: "Keramiklampen"}
          ],
          uri: "http://thesauri.dainst.org/_328cf29e"
        }
      },
      %{
        label: [],
        resource: %ArgosAggregation.Thesauri.Concept{
          id: "_6b00aec3",
          label: [%ArgosAggregation.TranslatedContent{lang: "de", text: "Vase"}],
          uri: "http://thesauri.dainst.org/_6b00aec3"
        }
      },
      %{
        label: [],
        resource: %ArgosAggregation.Thesauri.Concept{
          id: "_1342-l3",
          label: [
            %ArgosAggregation.TranslatedContent{
              lang: "de",
              text: "Plastik/Skulptur"
            }
          ],
          uri: "http://thesauri.dainst.org/_1342-l3"
        }
      }
    ],
    temporal: [],
    title: [
      %ArgosAggregation.TranslatedContent{lang: "de", text: "Fotoarchiv Berlin"},
      %ArgosAggregation.TranslatedContent{lang: "en", text: "Photoarchive Berlin"}
    ]
  }

  test "recreating project from json yields same result" do
    reconstructed =
      @example_project
      |> Poison.encode!()
      |> Poison.decode!()
      |> Project.Project.from_map()

    assert reconstructed == @example_project
  end

  test "get by id yields project" do
    record = Project.DataProvider.get_by_id("1")

    assert %Project.Project{} = record

    reconstructed =
      record
      |> Poison.encode!()
      |> Poison.decode!()
      |> Project.Project.from_map()

    assert reconstructed == record
  end

  test "get by id with invalid id yields error" do
    assert {:error, 404} == Project.DataProvider.get_by_id("-1")
    assert {:error, 400} == Project.DataProvider.get_by_id("not-a-number")
  end

  test "get all yields projects as result" do
    records =
      Project.DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn(record) ->
      assert %Project.Project{} = record
    end)
  end

  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "updating referenced thesauri concept updates bibliographic record" do
      ths_indexing_1 =
        Thesauri.DataProvider.get_by_id("_6b00aec3")
        |> fn ({:ok, concept}) -> concept end.()
        |> ElasticSearchIndexer.index()

      assert("created" == ths_indexing_1.upsert_response["result"])

      project_indexing =
        @example_project
        |> ElasticSearchIndexer.index()

      assert("created" == project_indexing.upsert_response["result"])

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      ths_indexing_2 =
        Thesauri.DataProvider.get_by_id("_6b00aec3")
        |> fn ({:ok, concept}) -> concept end.()
        |> Map.update!(
            :label, fn (old) -> old ++ [%TranslatedContent{ text: "Test name", lang: "de" }] end
          )
        |> ElasticSearchIndexer.index()

      assert("updated" == ths_indexing_2.upsert_response["result"])

      %{upsert_response: %{"_version" => project_new_version, "_id" => project_new_id}} =
        ths_indexing_2.referencing_docs_update_response
        |> List.first()

      %{"_version" => project_old_version, "_id" => project_old_id} = project_indexing.upsert_response

      assert project_old_version + 1 == project_new_version
      assert project_new_id == project_old_id
    end

    test "updating referenced gazetteer place updates bibliographic record" do
      gaz_indexing_1 =
        Gazetteer.DataProvider.get_by_id("2048575")
        |> fn ({:ok, place}) -> place end.()
        |> ElasticSearchIndexer.index()

      assert("created" == gaz_indexing_1.upsert_response["result"])

      project_indexing =
        @example_project
        |> ElasticSearchIndexer.index()

      assert("created" == project_indexing.upsert_response["result"])

      # Force refresh to make sure recently upserted docs are considered in search.
      TestHelpers.refresh_index()

      gaz_indexing_2 =
        Gazetteer.DataProvider.get_by_id("2048575")
        |> fn ({:ok, place}) -> place end.()
        |> Map.update!(
            :label, fn (old) -> old ++ [%TranslatedContent{ text: "Test name", lang: "de" }] end
          )
        |> ElasticSearchIndexer.index()

      assert("updated" == gaz_indexing_2.upsert_response["result"])

      %{upsert_response: %{"_version" => project_new_version, "_id" => project_new_id}} =
        gaz_indexing_2.referencing_docs_update_response
        |> List.first()

      %{"_version" => project_old_version, "_id" => project_old_id} = project_indexing.upsert_response

      assert project_old_version + 1 == project_new_version
      assert project_new_id == project_old_id
    end
  end
end
