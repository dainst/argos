defmodule ArgosAggregation.UpdateController do




  defmodule Observer do
    alias ArgosAggregation.UpdateController.Manager

    def updated_resource(resource, id)  do
      result = case resource do
        "gazetteer" -> Manager.process_updates("spatial", id)
        "chronontology" -> Manager.process_updates("temporal", id)
        "thesuarus" -> Manager.process_updates("subject", id)
        _ -> {:error, "no matching resource"}
      end
      result
    end



  end

  defmodule Manager do
    alias ArgosAggregation.Project

    @headers [{"Content-Type", "application/json"}]

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"

    def process_updates(filter, id) do
       find_relations(filter, id)
       |> handle_result
    end

    defp find_relations(filter, id) do
      query = get_query(filter, id)
      "#{@base_url}/_search"
      |> HTTPoison.post(query, @headers)

    end

    defp get_query(filter, id) do
      Poison.encode!(
        %{
          query: %{
            query_string: %{
              query: "#{id}",
                fields: ["#{filter}.resource.id"]
              }
            }
          }
        )
    end

    defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      data =
        body
        |> Poison.decode()
        |> transform_elasticsearch_response()
      {:ok, data}
    end

    defp transform_elasticsearch_response({:ok, %{"hits" => %{"hits" => hits }}}) do
      Enum.each(hits, &trigger_reloads(&1))
    end

    defp trigger_reloads(%{"_source" => %{"type" => "project", "id" => id}}) do
      Project.Harvester.reload(id)
    end
    #defp trigger_reloads(%{"_source" => %{"type" => "arachne_object", "id" => id}}) do
      #do something useful
    #end
  end

end
