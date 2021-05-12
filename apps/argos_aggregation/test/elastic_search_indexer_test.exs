defmodule ArgosAggregation.ElasticSearchIndexerTest do
  @moduledoc """
  Integration test for the indexing and updating of projects and update of subdocuments
  """
  use ExUnit.Case

  require Logger
  doctest ArgosAggregation.ElasticSearchIndexer

  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Chronontology.TemporalConcept
  alias ArgosAggregation.Thesauri.Concept
  alias ArgosAggregation.Project.Project
  alias ArgosAggregation.TranslatedContent
  alias ArgosAggregation.ElasticSearchIndexer
  alias ArgosAggregation.ElasticSearchIndexerTest.TestClient
  alias Geo.Point

  def create_dummy_project(%{id: id, spatial: s}) do
    pro = %Project{
      id: id,
      title: [ %TranslatedContent{ text: "Test Project #{id}", lang: "de" } ],
      spatial: [ %{ resource: s, label: [] }]
    }
    ElasticSearchIndexer.index(pro)
  end
  def create_dummy_project(%{id: id, temporal: t}) do
    pro = %Project{
      id: id,
      title: [ %TranslatedContent{ text: "Test Project #{id}", lang: "de" } ],
      temporal: [ %{ resource: t, label: [] } ]
    }
    ElasticSearchIndexer.index(pro)
  end
  def create_dummy_project(%{id: id, subject: c}) do
    pro = %Project{
      id: id,
      title: [ %TranslatedContent{ text: "Test Project #{id}", lang: "de" } ],
      subject: [ %{ resource: c, label: [] } ]
    }
    ElasticSearchIndexer.index(pro)
  end

  setup_all %{} do
    Logger.info("starting tests")
    Logger.info("creating test index")
    TestClient.create_test_index()
    TestClient.put_mapping()

    p = %Place{
      id: "2",
      uri: "gazetteer/place/to/be/2",
      label: [
        %TranslatedContent{ text: "Rom", lang: "de" },
        %TranslatedContent{ text: "Roma", lang: "it" }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    ElasticSearchIndexer.index(p)
    create_dummy_project(%{id: "1", spatial: p})

    t = %TemporalConcept{
      id: "1748",
      uri: "chronontology/time/to/be/1748",
      label: [
        %TranslatedContent{ text: "Pompeji", lang: "de" },
        %TranslatedContent{ text: "Pompei", lang: "it" }],
      beginning: 1748,
      ending: 1961
    }
    ElasticSearchIndexer.index(t)
    create_dummy_project(%{id: "2", temporal: t})

    c = %Concept{
      id: "_125",
      uri: "thesaurus/know/how/_125",
      label: [
        %TranslatedContent{ text: "Bauornamente", lang: "de" } ]
    }
    res = ElasticSearchIndexer.index(c)
    create_dummy_project(%{id: "3", subject: c})

    on_exit(fn ->
      Logger.info("delete test index")
      TestClient.delete_test_index()
    end)
    :ok
  end

  test "create project" do
    pro = %Project{
      id: 0,
      title: [ %TranslatedContent{ text: "Test Project 0", lang: "de" } ],
    }
    res = ElasticSearchIndexer.index(pro)
    assert %{"result" => "created", "_id" => "project-0"} = res
  end

  test "update project" do
    pro = %Project{
      id: 4,
      title: [ %TranslatedContent{ text: "Test Project 4", lang: "de" } ],
    }
    res = ElasticSearchIndexer.index(pro)
    assert %{"result" => "created", "_id" => "project-4"} = res

    TestClient.refresh_index()
    pro = TestClient.find_project(4)
    assert pro.title == [ %TranslatedContent{ text: "Test Project 4", lang: "de" } ]

    pro = %Project{
      id: 4,
      title: [ %TranslatedContent{ text: "Better Title for the Project", lang: "en" } ],
    }
    res = ElasticSearchIndexer.index(pro)
    assert %{"result" => "updated", "_id" => "project-4"} = res

    TestClient.refresh_index()
    pro = TestClient.find_project(4)
    assert pro.title == [ %TranslatedContent{ text: "Better Title for the Project", lang: "en" } ]

  end

  @doc """
  gazetteer tests
  """

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
    assert res == {:ok, "created"}
  end

  test "update gazzetteer with no known subdocuments" do
    p = %Place{
      id: "3",
      uri: "gazetteer/place/to/be/3",
      label: [
        %TranslatedContent{ text: "Paris", lang: "de"} ],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, "created"}

    p = %Place{
      id: "3",
      uri: "gazetteer/place/to/be/3",
      label: [
        %TranslatedContent{ text: "Paris", lang: "de" },
        %TranslatedContent{ text: "Parigi", lang: "it" } ],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, "no_subdocuments"}
  end

  test "update gazzetteer with a known subdocuments" do
    p = %Place{
      id: "2",
      uri: "gazetteer/place/to/be/2",
      label: [
        %TranslatedContent{ text: "Rom", lang: "de" },
        %TranslatedContent{ text: "Roma", lang: "it" },
        %TranslatedContent{ text: "Romsky", lang: "mz" }],
      geometry: Geo.JSON.encode!(
        %Point{ coordinates: {"41", "42"} }
        )
    }
    res = ElasticSearchIndexer.index(p)
    assert res == {:ok, "subdocs_updated"}

    pro_recieved = TestClient.find_project("1")
    pro_expected = %Project{
      id: "1",
      title: [ %TranslatedContent{ text: "Test Project 1", lang: "de" } ],
      spatial: [ %{ resource: p, label: [] } ]
    }
    assert pro_expected == pro_recieved
  end

  @doc """
  chronontology tests
  """

  test "add temporal" do
    t = %TemporalConcept{
      id: "1792",
      uri: "chronontology/time/to/be/1792",
      label: [
        %TranslatedContent{ text: "Amerika", lang: "de" },
        %TranslatedContent{ text: "Americano", lang: "it" } ],
      beginning: 1792,
      ending: 2016
    }
    res = ElasticSearchIndexer.index(t)
    assert res == {:ok, "created"}
  end

  test "update temporal no subdocs" do
    t = %TemporalConcept{
      id: "100",
      uri: "chronontology/time/to/be/100",
      label: [
        %TranslatedContent{ text: "1. Jh", lang: "de" },
        %TranslatedContent{ text: "1st Cent.", lang: "en" } ],
      beginning: 1,
      ending: 99
    }
    res = ElasticSearchIndexer.index(t)
    assert res == {:ok, "created"}

    t = %TemporalConcept{
      id: "100",
      uri: "chronontology/time/to/be/100",
      label: [
        %TranslatedContent{ text: "1. Jh", lang: "de" },
        %TranslatedContent{ text: "1st Cent.", lang: "en" } ],
      beginning: 1,
      ending: 100
    }
    res = ElasticSearchIndexer.index(t)
    assert res == {:ok, "no_subdocuments"}
  end

  test "update temporal with one subdocument" do
    t = %TemporalConcept{
      id: "1748",
      uri: "chronontology/time/to/be/1748",
      label: [
        %TranslatedContent{ text: "Pompeji", lang: "de" },
        %TranslatedContent{ text: "Pompei", lang: "it" },
        %TranslatedContent{ text: "Pompeii", lang: "en" } ],
      beginning: 1748,
      ending: 1961
    }
    res = ElasticSearchIndexer.index(t)
    assert res == {:ok, "subdocs_updated"}

    pro_recieved = TestClient.find_project("2")
    pro_expected = %Project{
      id: "2",
      title: [ %TranslatedContent{ text: "Test Project 2", lang: "de" } ],
      temporal: [ %{ resource: t, label: [] } ]
    }
    assert pro_expected == pro_recieved
  end

  @doc """
  thesaurus tests
  """

  test "add concept" do
    c = %Concept{
      id: "_123",
      uri: "thesaurus/know/how/_123",
      label: [
        %TranslatedContent{ text: "Keramik", lang: "de" },
        %TranslatedContent{ text: "Ceramic", lang: "en" } ],
    }
    res = ElasticSearchIndexer.index(c)
    assert res == {:ok, "created"}
  end

  test "update concept no subdocs" do
    c = %Concept{
      id: "_124",
      uri: "thesaurus/know/how/_124",
      label: [
        %TranslatedContent{ text: "Tafelgeschirr", lang: "de" },
        %TranslatedContent{ text: "Tableware", lang: "en" } ],
    }
    res = ElasticSearchIndexer.index(c)
    assert res == {:ok, "created"}

    c = %Concept{
      id: "_124",
      uri: "thesaurus/know/how/_124",
      label: [
        %TranslatedContent{ text: "Tafelgeschirr", lang: "de" },
        %TranslatedContent{ text: "Tableware", lang: "en" },
        %TranslatedContent{ text: "Stoviglie", lang: "it" }, ],
    }
    res = ElasticSearchIndexer.index(c)
    assert res == {:ok, "no_subdocuments"}
  end

  test "update comcept with one subdocument" do
    c = %Concept{
      id: "_125",
      uri: "thesaurus/know/how/_125",
      label: [
        %TranslatedContent{ text: "Bauornamente", lang: "de" },
        %TranslatedContent{ text: "ornamenti di edifici", lang: "it" } ],
    }
    res = ElasticSearchIndexer.index(c)
    assert res == {:ok, "subdocs_updated"}

    pro_recieved = TestClient.find_project("3")
    pro_expected = %Project{
      id: "3",
      title: [ %TranslatedContent{ text: "Test Project 3", lang: "de" } ],
      subject: [ %{ resource: c, label: [] } ]
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

    def add_settings() do
      q = Poison.encode!(%{
        index: %{
          refresh_interval: "1ms"
        }
      })
      "#{@base_url}#{@index_name}/_settings"
      |> HTTPoison.put!(q)
    end

    def refresh_index() do
      "#{@base_url}#{@index_name}/_refresh"
      |> HTTPoison.post!("")
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
      refresh_index() # crucial for the test to work since updates might not be visible for search

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
      Project.create_project(proj)
    end

    def search_for_subdocument(type, id) do
      refresh_index() # crucial for test to work since update might not be visible for search

      ElasticSearchClient.search_for_subdocument(type, id)
    end
  end
end
