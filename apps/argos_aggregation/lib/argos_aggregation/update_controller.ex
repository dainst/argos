defmodule ArgosAggregation.UpdateController do

  defmodule Observer do
    use Agent
    #alias ArgosAggregation.UpdateController.Manager

    def start_link(opts) do
      {init_val, opts} = Keyword.pop(opts, :init_val, %{"spatial" => [], "temporal" => [], "subject" => []})
      Agent.start_link(fn -> init_val end, opts)
    end


    def updated_resource(name, resource, id)  do
      Agent.update(name, fn(id_maps) ->
        case resource do
          "gazetteer" -> Map.update!(id_maps, "spatial", fn cur -> [id | cur ] end)
          "chronontology" -> Map.update!(id_maps, "temporal", fn cur -> [id | cur ] end)
          "thesuarus" -> Map.update!(id_maps, "subject", fn cur -> [id | cur ] end)
          _ -> {:error, "no matching resource"}
        end
      end
      )
    end

    def get_resource_ids(name) do
      Agent.get(name, fn map -> map end)
    end

  end

  defmodule Manager do
    alias ArgosAggregation.Project

    @headers [{"Content-Type", "application/json"}]

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"

    def process_updates(updated_ids) do
      Enum.each(updated_ids, fn({key, val}) ->
        find_relations(key, val)
        |> handle_result
      end )
    end

    defp find_relations(_filter, [] = _ids) do {:error, nil} end
    defp find_relations(filter, ids) do
      query = get_query(filter, ids)
      "#{@base_url}/_search"
      |> HTTPoison.post(query, @headers)
      |> IO.inspect
    end

    defp get_query(filter, ids) do
      s_id = Enum.join(ids, " OR ")
      Poison.encode!(
        %{
          query: %{
            query_string: %{
              query: s_id,
                fields: ["#{filter}.resource.id"]
              }
            }
          }
        )
    end

    defp handle_result({:ok, nil}) do {:ok, :ok} end
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
