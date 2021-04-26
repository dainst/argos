defmodule ArgosAggregation.UpdateController do
  require Logger

  defmodule Observer do
    use Agent
    #alias ArgosAggregation.UpdateController.Manager


    def start_link(opts) do
      {init_val, opts} = Keyword.pop(opts, :init_val, %{spatial: MapSet.new(), temporal: MapSet.new(), subject: MapSet.new()})
      Agent.start_link(fn -> init_val end, name: :update_observer)
    end

    def updated_resource(resource, id)  do
      key = get_resource_key(resource) # loading the key outside the Agent preventing unnecessary delays
      # updates the state of the agent
      Agent.update(:update_observer, fn(id_map) -> update_vals(key, id_map, id) end)
    end

    def del_resource_ids(resource, ids) do
      key = get_resource_key(resource) # see above
      Agent.update(:update_observer, fn id_map -> delete_vals(key, id_map, ids) end)
    end


    def get_resource_ids() do
      # returns everything the whole map
      Agent.get(:update_observer, fn map -> map end)
    end


    def get_resources_ids(resource) do
      key = get_resource_key(resource)
      Agent.get(:update_observer, fn map -> map[key] end)
    end


    defp get_resource_key(res) do
      case res do
        "gazetteer" -> {:ok, :spatial}
        "chronontology" -> {:ok, :temporal}
        "thesuarus" -> {:ok, :subject}
        _ -> {:error, "no matching resource"}
      end
    end

     # update vals adds a new id to the set under the specific key
    defp update_vals({:ok, key}, map, new_id), do: Map.update!(map, key, fn cur -> cur.put(new_id) end)
    defp update_vals({:error, reason}, _map, _new_id), do: Logger.error(reason)

    # delete vals erases all given values from the set under the specific key
    defp delete_vals({:ok, key}, map, old_ids), do: Map.update!(map, key, fn cur -> MapSet.difference(cur, old_ids)  end)
    defp delete_vals({:error, reason}, _map, _new_id), do: Logger.error(reason)
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
