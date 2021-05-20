defmodule ArgosAggregation.BibliographyTest do
  use ExUnit.Case

  require Logger
  doctest(ArgosAggregation.Bibliography)

  alias ArgosAggregation.{
    Gazetteer, Thesauri, Bibliography, ElasticSearchIndexer, TranslatedContent, TestHelpers
  }

  @bibliography_record %Bibliography.BibliographicRecord{
      title:
        %{
          text: "Morminte geto-dacice descoperite în judeţul Călăraşi.",
          lang: "ro"
        },
      subject: [
        %{
          resource: %{
            uri: "http://thesauri.dainst.org/_b7707545",
            label:
            [
              %{
                text: "Beigabensitten", lang: "de"
              }
            ],
            id: "_b7707545"
          },
          label: "subject_heading"
        }
      ],
      spatial: [
        %{
          resource: %{
            uri: "https://gazetteer.dainst.org/place/2067337",
            label:
              [
                %{
                  text: "Călărasi (jud.)", lang: "de"
                }
              ],
            id: "2067337",
            geometry: []
          },
          label: "subject_heading"
        }
      ],
      persons: [
        %{
          uri: "",
          label: %{
            text: "Serbanescu, Done",
            lang: ""
          }
        }
      ],
      institutions: [],
      id: "001294207",
      full_record: %{}
    }

  setup %{} do
    TestHelpers.create_index()

    on_exit(fn ->
      TestHelpers.remove_index()
    end)
    :ok
  end

  test "updating referenced thesauri concept updates bibliographic record" do
    ths_indexing_1 =
      Thesauri.DataProvider.get_by_id("_b7707545")
      |> fn ({:ok, concept}) -> concept end.()
      |> ElasticSearchIndexer.index()

    assert("created" == ths_indexing_1.upsert_response["result"])

    biblio_indexing =
      @bibliography_record
      |> ElasticSearchIndexer.index()

    assert("created" == biblio_indexing.upsert_response["result"])

    # Force refresh to make sure recently upserted docs are considered in search.
    TestHelpers.refresh_index()

    ths_indexing_2 =
      Thesauri.DataProvider.get_by_id("_b7707545")
      |> fn ({:ok, concept}) -> concept end.()
      |> Map.update!(
          :label, fn (old) -> old ++ [%TranslatedContent{ text: "Test name", lang: "de" }] end
        )
      |> ElasticSearchIndexer.index()

    assert("updated" == ths_indexing_2.upsert_response["result"])

    %{"_version" => biblio_new_version, "_id" => biblio_new_id} =
      ths_indexing_2.reference_update_response
      |> List.first()

    %{"_version" => biblio_old_version, "_id" => biblio_old_id} = biblio_indexing.upsert_response

    assert biblio_old_version + 1 == biblio_new_version
    assert biblio_new_id == biblio_old_id
  end


  test "updating referenced gazetteer place updates bibliographic record" do
    gaz_indexing_1 =
      Gazetteer.DataProvider.get_by_id("2067337")
      |> fn ({:ok, place}) -> place end.()
      |> ElasticSearchIndexer.index()

    assert("created" == gaz_indexing_1.upsert_response["result"])

    biblio_indexing =
      @bibliography_record
      |> ElasticSearchIndexer.index()

    assert("created" == biblio_indexing.upsert_response["result"])

    # Force refresh to make sure recently upserted docs are considered in search.
    TestHelpers.refresh_index()

    gaz_indexing_2 =
      Gazetteer.DataProvider.get_by_id("2067337")
      |> fn ({:ok, place}) -> place end.()
      |> Map.update!(
          :label, fn (old) -> old ++ [%TranslatedContent{ text: "Test name", lang: "de" }] end
        )
      |> ElasticSearchIndexer.index()

    assert("updated" == gaz_indexing_2.upsert_response["result"])

    %{"_version" => biblio_new_version, "_id" => biblio_new_id} =
      gaz_indexing_2.reference_update_response
      |> List.first()

    %{"_version" => biblio_old_version, "_id" => biblio_old_id} = biblio_indexing.upsert_response

    assert biblio_old_version + 1 == biblio_new_version
    assert biblio_new_id == biblio_old_id
  end
end
