defmodule ArgosAggregation.ElasticSearchIndexerTest do
  use ExUnit.Case
  doctest ArgosAggregation.ElasticSearchIndexer

  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Project.Project
  alias ArgosAggregation.TranslatedContent
  alias ArgosAggregation.ElasticSearchIndexerTest.TestClient
  alias Geo.Point

  setup_all %{} do
    IO.puts("starting tests")
    IO.puts("creating test index")
    TestClient.create_test_index()

    on_exit(fn ->
      IO.puts("delete test index")
      TestClient.delete_test_index()
    end)
    :ok
  end

  test "add gazzetteer" do
    p = %Place{
      id: 1,
      uri: "gazetteer/place/to/be/1",
      label: [ %TranslatedContent{
        text: "Berlin",
        lang: "de"
      } ],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {41, 42} }
        )
    }
    res = ArgosAggregation.ElasticSearchIndexer.index(p)
    assert res == {:ok, nil}
  end

  test "update gazzetteer with no known subdocuments" do
    p = %Place{
      id: 1,
      uri: "gazetteer/place/to/be/1",
      label: [ %TranslatedContent{
        text: "Berlin",
        lang: "de"
      } , %TranslatedContent{
        text: "Berlino",
        lang: "it"
      }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {41, 42} }
        )
    }
    res = ArgosAggregation.ElasticSearchIndexer.index(p)
    assert res == {:ok, nil}
  end

  setup %{} do
    IO.puts("create dummy project")
    pro = %Project{
      id: 1,
      title: [%TranslatedContent{
        text: "Test Project",
        lang: "de"
      }],
      spatial: [%Place{
        id: 1,
        uri: "gazetteer/place/to/be/1",
        label: [ %TranslatedContent{
          text: "Berlin",
          lang: "de"
        } , %TranslatedContent{
          text: "Berlino",
          lang: "it"
        } ],
        geometry: Geo.JSON.encode!(
          %Point{ coordinates: {41, 42} }
          )
      }]
    }
    resp = ArgosAggregation.ElasticSearchIndexer.index(pro)
    IO.inspect(resp)
    :ok
  end

  test "update gazzetteer with a known subdocuments" do
    p = %Place{
      id: 1,
      uri: "gazetteer/place/to/be/1",
      label: [ %TranslatedContent{
        text: "Berlin",
        lang: "de"
      } , %TranslatedContent{
        text: "Berlino",
        lang: "it"
      }, %TranslatedContent{
        text: "Berolino",
        lang: "es"
      }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {41, 42} }
        )
    }
    res = ArgosAggregation.ElasticSearchIndexer.index(p)
    assert res == {:ok, %HTTPoison.Response{status_code: 200}}
  end


  @moduledoc """
  Testclient is a wrapper for the actual client
  allowing to create and delete indexes for testing
  """
  defmodule TestClient do
    alias ArgosAggregation.ElasticSearchIndexer.ElasticSearchClient

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}"
    @index_name "/#{Application.get_env(:argos_api, :index_name)}"


    def create_test_index() do
      "#{@base_url}#{@index_name}"
      |> HTTPoison.put!
    end

    def delete_test_index() do
      "#{@base_url}#{@index_name}"
      |> HTTPoison.delete!
    end

    def upsert(payload) do
      ElasticSearchClient.upsert(payload)
    end

    def check_created() do
      query = Poison.encode!( %{ query: %{ match_all: %{} } } )
      "#{@base_url}#{@index_name}/_search"
      |> HTTPoison.post(query, [{"Content-Type", "application/json"}])
    end

    def create_project(proj) do

    end

    def search_for_subdocument(type, id) do
      ElasticSearchClient.search_for_subdocument(type, id)
    end
  end
end
