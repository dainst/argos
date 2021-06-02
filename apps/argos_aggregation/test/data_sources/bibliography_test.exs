defmodule ArgosAggregation.BibliographyTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosAggregation.Bibliography)

  alias ArgosAggregation.{
    Gazetteer, Thesauri, Bibliography, Bibliography.BibliographicRecord, ElasticSearchIndexer, CoreFields, TestHelpers
  }

  @zenon_data %{
    "authors" => %{
        "primary" => %{
            "Robinson, Mark" => %{
                "role" => [
                    "aut"
                ]
            },
            "Trümper, Monika" => %{
                "role" => [
                    "aut"
                ]
            },
            "Brünenberg, Clemens" => %{
                "role" => [
                    "aut"
                ]
            },
            "Dickmann, Jens-Arne" => %{
                "role" => [
                    "aut"
                ]
            },
            "Esposito, Domenico" => %{
                "role" => [
                    "aut"
                ]
            },
            "Ferrandes, Antonio F." => %{
                "role" => [
                    "aut"
                ]
            },
            "Pardini, Giacomo" => %{
                "role" => [
                    "aut"
                ]
            },
            "Rummel, Christoph" => %{
                "role" => [
                    "aut"
                ]
            },
            "Pegurri, Alessandra" => %{
                "role" => [
                    "aut"
                ]
            }
        },
        "secondary" => [],
        "corporate" => []
    },
    "primaryAuthorsNames" => [
        "Robinson, Mark"
    ],
    "secondaryAuthorsNames" => [
        "Trümper, Monika"
    ],
    "corporateAuthorsNames" => [],
    "bibliographicLevel" => "SerialPart",
    "bibliographyNotes" => [],
    "callNumbers" => [],
    "formats" => [
        "Article"
    ],
    "generalNotes" => [],
    "id" => "002023387",
    "isbns" => [],
    "issns" => [
        "2510-4713"
    ],
    "languages" => [
        "English"
    ],
    "publicationDates" => [
        "2021"
    ],
    "publishers" => [
        "Deutsches Archäologisches Institut,"
    ],
    "series" => [],
    "shortTitle" => "Stabian Baths in Pompeii. New Research on the Archaic Defenses of the City ",
    "subjects" => [
        [
            "Pompeji", "Bäder"
        ]
    ],
    "summary" => [
        "The plan of the Archaic city of Pompeii and the existence of a distinct walled Altstadt have been much debated in scholarship. The area of the Stabian Baths plays a key role in this debate. Based on a series of excavations in the palaestra of the baths, Heinrich Sulze (1940) and particularly Hans Eschebach (1970s) reconstructed a defensive wall and parallel ditch in this area. Eschebach also identified an Archaic street and city gate in the northern part of the baths. While Eschebach’s reconstruction was challenged by later research, the evidence and his interpretation of his trenches have never been systematically reassessed. It is the aim of this paper to fill this crucial gap. Based on the re-exposition of Sulze’s and Eschebach’s archaeological contexts and new excavations it is shown that no traces of an Archaic wall, robber trench, palisade, or ditch or of any other Archaic features can be securely identified in the area of the Stabian Baths. Focus here is on a key trench in the palaestra (Area III) that had been excavated by both Sulze and Eschebach and provides the most important insights into the development and use of this terrain, from the Bronze Age to A.D. 79. The archaeological contexts are described in detail and interpreted particularly with a view to the early history of Pompeii, and more briefly with a view to the development of the baths."
    ],
    "title" => "Stabian Baths in Pompeii. New Research on the Archaic Defenses of the City ",
    "urls" => [
        %{
            "url" => "https:///nbn-resolving.org//urn:nbn:de:0048-aa.v0i2.1023.7",
            "desc" => "Available online "
        }
    ],
    "containerPageRange" => "1-201365",
    "additionalInformation" => [],
    "parentId" => "002023378",
    "thesaurus" => [],
    "DAILinks" => %{
        "gazetteer" => [
            %{
                "label" => "Pompeji",
                "uri" => "https://gazetteer.dainst.org/place/2338718"
            }
        ],
        "thesauri" => [
          %{
            "label" => "Bäder",
            "uri" => "http://thesauri.dainst.org/_031c59e9"
          }
        ]
    },
    "lastIndexed" => "2021-02-24T03:04:18Z"
  }

  test "get by id yields bibliographic record" do
    id = "002023378"

    {:ok, record } =
      id
      |> Bibliography.DataProvider.get_by_id()
      |> Bibliography.BibliographicRecord.create()

      assert %Bibliography.BibliographicRecord{ core_fields: %CoreFields{source_id: ^id}} = record
  end

  test "get by id with invalid id yields error" do
    assert {:error, "record not-existing not found."} == Bibliography.DataProvider.get_by_id("not-existing")
  end

  test "get all yields bibliographic records as result" do
    records =
      Bibliography.DataProvider.get_all()
      |> Enum.take(10)

    assert Enum.count(records) == 10

    records
    |> Enum.each(fn(record) ->
      assert {:ok, %BibliographicRecord{}} = BibliographicRecord.create(record)
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

      ths_data = Thesauri.DataProvider.get_by_id("_031c59e9")

      ths_indexing = ElasticSearchIndexer.index(ths_data)

      assert("created" == ths_indexing.upsert_response["result"])

      biblio_indexing =
        @zenon_data
        |> Bibliography.BibliographyParser.parse_record()
        |> ElasticSearchIndexer.index()

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
        |> ElasticSearchIndexer.index()

      assert("updated" == ths_indexing.upsert_response["result"])

      %{upsert_response: %{"_version" => biblio_new_version, "_id" => biblio_new_id}} =
        ths_indexing.referencing_docs_update_response
        |> List.first()

      %{"_version" => biblio_old_version, "_id" => biblio_old_id} = biblio_indexing.upsert_response

      assert biblio_old_version + 1 == biblio_new_version
      assert biblio_new_id == biblio_old_id
    end


    test "updating referenced gazetteer place updates bibliographic record" do
      gaz_data = Gazetteer.DataProvider.get_by_id("2338718")

      gaz_indexing = ElasticSearchIndexer.index(gaz_data)

      assert("created" == gaz_indexing.upsert_response["result"])

      biblio_indexing =
        @zenon_data
        |> Bibliography.BibliographyParser.parse_record()
        |> ElasticSearchIndexer.index()

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
        |> ElasticSearchIndexer.index()

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
