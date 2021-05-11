defmodule ArgosAggregation.ElasticSearchIndexerTest do
  use ExUnit.Case

  require Logger
  doctest ArgosAggregation.ElasticSearchIndexer

  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Project.Project
  alias ArgosAggregation.TranslatedContent
  alias ArgosAggregation.ElasticSearchIndexer
  alias ArgosAggregation.ElasticSearchIndexerTest.TestClient
  alias Geo.Point

  setup_all %{} do
    Logger.info("starting tests")
    Logger.info("creating test index")
    TestClient.create_test_index()
    TestClient.put_mapping()

    Logger.info("create dummy gazetteer")
    p = %Place{
      id: "2",
      uri: "gazetteer/place/to/be/2",
      label: [  %TranslatedContent{
        text: "Rom",
        lang: "de"
      } , %TranslatedContent{
        text: "Roma",
        lang: "it"
      }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    ElasticSearchIndexer.index(p)

    Logger.info("create dummy project")
    pro = %Project{
      id: "1",
      title: [ %TranslatedContent{ text: "Test Project", lang: "de" } ],
      spatial: [
        %{
          resource: p,
          label: []
        }
      ]
    }
    ElasticSearchIndexer.index(pro)
    :timer.sleep(1000)
    # crucial for the test to run properly
    # since there is a delay in indexing

    on_exit(fn ->
      Logger.info("delete test index")
      TestClient.delete_test_index()
    end)
    :ok
  end

  test "add gazzetteer" do
    p = %Place{
      id: "1",
      uri: "gazetteer/place/to/be/1",
      label: [ %TranslatedContent{
        text: "Berlin",
        lang: "de"
      } ],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, nil}
  end

  test "update gazzetteer with no known subdocuments" do
    p = %Place{
      id: "1",
      uri: "gazetteer/place/to/be/1",
      label: [ %TranslatedContent{
        text: "Berlin",
        lang: "de"
      } , %TranslatedContent{
        text: "Berlino",
        lang: "it"
      }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, nil}
  end

  test "update gazzetteer with a known subdocuments" do
    p = %Place{
      id: "2",
      uri: "gazetteer/place/to/be/2",
      label: [  %TranslatedContent{
        text: "Rom",
        lang: "de"
      } , %TranslatedContent{
        text: "Roma",
        lang: "it"
      }, %TranslatedContent{
        text: "Romsky",
        lang: "mz"
      }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, "all_done"}
    :timer.sleep(1000)
    pro_recieved = TestClient.find_project("1")

    pro_expected = %Project{
      id: "1",
      title: [ %TranslatedContent{ text: "Test Project", lang: "de" } ],
      spatial: [
        %{
          resource: p,
          label: []
        }
      ]
    }

    assert pro_expected == pro_recieved
  end



  @moduledoc """
  Testclient is a wrapper for the actual client
  allowing to create and delete indexes for testing
  """
  defmodule TestClient do
    alias ArgosAggregation.ElasticSearchIndexer.ElasticSearchClient

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}"
    @index_name "/#{Application.get_env(:argos_api, :index_name)}"
    @elasticsearch_url "#{@base_url}#{@index_name}"
    @elasticsearch_mapping_path Application.get_env(:argos_api, :elasticsearch_mapping_path)


    def create_test_index() do
      "#{@base_url}#{@index_name}"
      |> HTTPoison.put!
      put_mapping()
    end

    def delete_test_index() do
      "#{@base_url}#{@index_name}"
      |> HTTPoison.delete!
    end

    def put_mapping() do
      mapping = File.read!("../../#{@elasticsearch_mapping_path}")

      "#{@elasticsearch_url}/_mapping"
      |> HTTPoison.put(mapping, [{"Content-Type", "application/json"}])
    end

    def upsert(payload) do
      ElasticSearchClient.upsert(payload)
    end

    def find_project(pid) do
      query = Poison.encode!(
        %{
          query: %{
            query_string: %{
              query: "type:project AND id:#{pid}" }
            }
        } )
      "#{@base_url}#{@index_name}/_search"
      |> HTTPoison.post(query, [{"Content-Type", "application/json"}])
      |> parse_body
    end


    defp parse_body({:ok, %HTTPoison.Response{body: body}}) do
      %{"hits" => %{"hits" => [pro|_]}} = Poison.decode!(body)
      proj = pro["_source"]
      #pro_map = for {key, val} <- proj, into: %{}, do: {String.to_atom(key), val}
      #struct(Project, pro_map)
      Project.create_project(proj)
    end

    def search_for_subdocument(type, id) do
      ElasticSearchClient.search_for_subdocument(type, id)
    end
  end
end
