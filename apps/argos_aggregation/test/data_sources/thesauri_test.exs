defmodule ArgosAggregation.ThesauriTest do
  use ExUnit.Case

  require Logger

  doctest ArgosAggregation.Thesauri

  alias ArgosAggregation.Thesauri.{
    Concept,
    DataProvider,
    ConceptParser,
    Harvester
  }

  alias ArgosAggregation.CoreFields
  alias ArgosAggregation.TestHelpers


  describe "dataprovider tests" do
    test "get by id yields concept with requested id" do
      id = "_b7707545"

      {:ok, concept} =
        with {:ok, params} <- DataProvider.get_by_id(id) do
          params |> Concept.create()
        end

      assert %Concept{core_fields: %CoreFields{source_id: ^id}} = concept
    end

    @tag timeout: :infinity
    test "get all yields list of concepts" do
      records =
        DataProvider.get_all()
        |> Enum.take(10)

      assert Enum.count(records) == 10
      records
      |> Enum.each(fn({:ok, record}) ->
        assert {:ok, %Concept{}} = Concept.create(record)
      end)
    end

    test "get by date yields concept as result" do
      records  =
        DataProvider.get_by_date(~D[2021-01-01])
        |> Enum.take(10)

      assert Enum.count(records) == 10

      records
      |> Enum.each(fn({:ok, record}) ->
        assert {:ok, %Concept{}} = Concept.create(record)
      end)
    end

    test "get by tomorrow yields empty list" do
      records  =
        Date.utc_today()
        |> Date.add(1)
        |> DataProvider.get_by_date()
        |> Enum.to_list()

      assert Enum.count(records) == 0

    end

    test "get by id with invalid id yields 404" do
      invalid_id = "i-am-non-existant"

      error = DataProvider.get_by_id(invalid_id)

      expected_error = {
        :error,
        "Received unhandled status code 404."
      }
      assert expected_error == error
    end
  end

  describe "elastic search integration tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "concept can be added to index" do
      {:ok, concept} = DataProvider.get_by_id("_b7707545")

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(concept)

      assert %{
        upsert_response: %{"_id" => "concept__b7707545", "result" => "created"}
      } = indexing_response
    end

    test "concept can be reloaded locally" do
      id = "_b7707545"

      # First, load from concept, manually add another label variant and push to index.
      case DataProvider.get_by_id(id) do
        {:ok, params} ->
          params
          |> Map.update!(
            "core_fields",
            fn (old_core) ->
              Map.update!(
                old_core,
                "title",
                fn (old_title) ->
                  old_title ++ [%{"text" => "Test name", "lang" => "mz"}]
                end)
            end)
          |> ArgosAggregation.ElasticSearch.Indexer.index()
      end


      # Now reload both locally and from iDAI.gazetteer.
      {:ok, concept_from_index} =
        id
        |> DataProvider.get_by_id(false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()
      {:ok, concept_from_thesaurus} =
        id
        |> DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      # Finally compare the title field length.
      assert length(concept_from_index.core_fields.title) - 1 == length(concept_from_thesaurus.core_fields.title)
    end

    test "if concept was requested to be loaded locally, but was missing in the index, it is also automatically indexed" do
      {:ok, concept } =
        DataProvider.get_by_id("_8bca4bf1", false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      TestHelpers.refresh_index()

      assert {:ok, _concept_from_index} = ArgosAggregation.ElasticSearch.DataProvider.get_doc(concept.core_fields.id)
    end

    test "harvester index by date" do
      result =
        Date.utc_today()
        |> Date.add(-7)
        |> Harvester.run_harvest
      assert :ok = result
    end
  end

  describe "concept parser tests" do
    test "validator accept valid xml" do
      body = File.read!("test/data_sources/xml_test_files/valid_rdf.xml")
      assert {:ok,_} = ConceptParser.Utils.check_validity(body)
    end

    test "validator refutes invalid xml" do
      body = File.read!("test/data_sources/xml_test_files/invalid_rdf.xml")
      assert {:error, "Malformed xml document"} = ConceptParser.Utils.check_validity(body)
    end

    test "parse search result" do
      with {:ok, body} <- File.read("test/data_sources/xml_test_files/test_valid_search_rdf.xml") do
        url = ConceptParser.Search.load_first_page_url(body)
        assert 'http://thesauri.dainst.org/search.rdf?change_note_date_from=2021-01-01&page=1&q=' == url

        {doc_list, next_url} = ConceptParser.Search.load_next_page_items(body)
        assert 'http://thesauri.dainst.org/search.rdf?change_note_date_from=2021-01-01&page=2&q=' == next_url

        assert 10 = length(doc_list)
        [doc|_] = doc_list

        assert {:ok, concept} = ConceptParser.Search.parse_single_doc(doc)
        assert %{ "core_fields" => %{ "source_id" =>  "_d00629a7",  "title" => [%{"lang" => "de", "text" => "fett"}]} } = concept
      else
        {:error, error} -> raise error
      end
    end

    test "pars root level from hierarchy" do
      roots =
        File.read!("test/data_sources/xml_test_files/root_level_hierarchy.rdf")
        |> ConceptParser.Hierarchy.read_root_level()

      assert 4 = length(roots)
    end

    test "parse single document" do
      with {:ok, body} <- File.read("test/data_sources/xml_test_files/valid_hierarchy.rdf") do
        assert {:ok, doc} = ConceptParser.read_single_document(body, "_e7ad4447")
        assert %{ "core_fields" => %{
          "source_id" => "_e7ad4447",
          "title" => [
            %{"lang" => "de", "text" => "Archäologie"},
            %{"lang" => "en", "text" => "archaeology"},
            %{"lang" => "it", "text" => "archeologia"},
            %{"lang" => "fr", "text" => "archéologie"},
            %{"lang" => "uk", "text" => "Археологія"},
            %{"lang" => "ru", "text" => "Археология"},
            %{"lang" => "ar", "text" => "علم الآثار"}
          ]} } = doc
      else
        {:error, error} -> raise error
      end
    end

    test "parse invalid document" do
      with {:ok, body} <- File.read("test/data_sources/xml_test_files/invalid_documents.rdf") do
        # missing lang attribute
        assert {:ok, doc} = ConceptParser.read_single_document(body, "_39260fea")
        assert %{ "core_fields" => %{
          "source_id" => "_39260fea",
                "title" => [
                  %{"lang" => "de", "text" => "Methoden"},
                  %{"lang" => "", "text" => "méthodes"},
                  %{"lang" => "en", "text" => "methods and theory"},
                  %{"lang" => "it", "text" => "metodi"}
                ]} } = doc

        #misspelled lang attribute
        assert {:ok, doc} = ConceptParser.read_single_document(body, "_5a1e0444")
        assert %{ "core_fields" => %{
          "source_id" => "_5a1e0444",
                "title" => [
                  %{"lang" => "de", "text" => "Sprachen"},
                  %{"lang" => "it", "text" => "altre lingue"},
                  %{"lang" => "", "text" => "autres langues"},
                  %{"lang" => "en", "text" => "other languages"}
                ]} } = doc

        #missing label text
        assert {:ok, doc} = ConceptParser.read_single_document(body, "_fe65f286")
        assert %{ "core_fields" => %{
                "source_id" => "_fe65f286",
                "title" => [%{"lang" => "de", "text" => ""}, %{"lang" => "en", "text" => "iDAI.world thesaurus"}]} } = doc

        #try to hit the missing id
        descriptions = ConceptParser.Hierarchy.read_list_of_descriptions(body)
        assert is_list(descriptions)
        assert {:ok, doc} = List.last(descriptions)
        assert %{ "core_fields" => %{
          "source_id" => "", "title" => [
            %{"lang" => "de", "text" => "Fiktionale und übernatürliche Wesen"},
            %{"lang" => "it", "text" => "dei e figure mitologiche"},
            %{"lang" => "fr", "text" => "dieux et personnages mythologiques"},
            %{"lang" => "en", "text" => "gods and mythological figurs"}]} } = doc
      else
        {:error, error} -> raise error
      end
    end

    test "parse hierarchy result" do
      with {:ok, body} <- File.read("test/data_sources/xml_test_files/valid_hierarchy.rdf") do
        descriptions = ConceptParser.Hierarchy.read_list_of_descriptions(body)
        assert is_list(descriptions)
        [{:ok, concept}|_] = descriptions
        assert %{ "core_fields" => %{ "source_id" => "_b189d13f", "title" => [%{"lang" => "de", "text" => "Afrikanische Archäologie"}]} } = concept
      else
        {:error, error} -> raise error
      end
    end
  end


  describe "elastic search tests" do

    setup %{} do
      TestHelpers.create_index()

      on_exit(fn ->
        TestHelpers.remove_index()
      end)
      :ok
    end

    test "concept can be added to index" do
      {:ok, concept} = DataProvider.get_by_id("_b7707545")

      indexing_response = ArgosAggregation.ElasticSearch.Indexer.index(concept)

      assert %{
        upsert_response: %{"_id" => "concept__b7707545", "result" => "created"}
      } = indexing_response
    end

    test "concept can be reloaded locally" do
      id = "_b7707545"

      # First, load from Thesauri, manually add another title variant and push to index.
      DataProvider.get_by_id(id)
      |> case do
        {:ok, params} -> params
      end
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
      |> ArgosAggregation.ElasticSearch.Indexer.index()

      # Now reload both locally and from thesauri
      {:ok, concept_from_index} =
        id
        |> DataProvider.get_by_id(false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()
      {:ok, concept_from_thesauri} =
        id
        |> DataProvider.get_by_id()
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      # Finally compare the title field length.
      assert length(concept_from_index.core_fields.title) - 1 == length(concept_from_thesauri.core_fields.title)
    end

    test "if concept was requested to be loaded locally, but was missing in the index, it is also automatically indexed" do
      {:ok, concept } =
        DataProvider.get_by_id("_b7707545", false)
        |> case do
          {:ok, params} -> params
        end
        |> Concept.create()

      TestHelpers.refresh_index()

      assert {:ok, _concept_from_index} = ArgosAggregation.ElasticSearch.DataProvider.get_doc(concept.core_fields.id)
    end
  end

end
