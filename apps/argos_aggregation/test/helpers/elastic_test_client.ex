
 defmodule Helpers.ElasticTestClient do

 @moduledoc """
  Testclient is a wrapper for the actual client
  allowing to create and delete indexes for testing
  """
    alias ArgosAggregation.ElasticSearchIndexer.ElasticSearchClient
    alias ArgosAggregation.Project.Project

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

      Poison.encode!(
        %{
          query: %{
            query_string: %{
              query: "type:project AND id:#{pid}" }
            }
        } )
      |> search_index
    end

    def find_gazetteer(gid) do
      refresh_index() # crucial for the test to work since updates might not be visible for search
      %{
        query: %{
          query_string: %{
            query: "type:place AND id:#{gid}" }
          }
      }
      |> Poison.encode!
      |> search_index
    end

    def find_all() do
      refresh_index()

      %{ "query": %{ "match_all": %{} } }
      |> Poison.encode!
      |> search_index
    end

    defp search_index(query) do
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
