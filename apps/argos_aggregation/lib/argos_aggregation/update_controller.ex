defmodule ArgosAggregation.UpdateController do
  @moduledoc """
  This module provides two submodules for handling the updated process of the denormalized documents in the elastic-search index
  """
  require Logger

  defmodule Observer do
    @moduledoc """
    The observer is an `Agent` that provides the possibility for harvesters and other modules
    in the `ArgosAggregation` project to store and read ids of recently changed documents
    """
    use Agent

   @doc """
   start_link starts the agent.
   Usally this method is envoked by the `Application.start/2` method
   The default init value of the agent is a Map of MapSets, therefore every key links to a unique set of ids
   """
    def start_link(opts) do
      {init_val, opts} = Keyword.pop(opts, :init_val, %{spatial: MapSet.new(), temporal: MapSet.new(), subject: MapSet.new()})
      Agent.start_link(fn -> init_val end, name: :update_observer)
    end

    @doc """
    Adds another Id of the given resource to the currently stored set of ids
    !important: Ids are stored as MapSet to prevent duplicates. Adding the same id twice will have no effect.

    Returns always `:ok`
    """
    def add_resource_id(resource, id)  do
      key = get_resource_key(resource) # loading the key outside the Agent preventing unnecessary delays
      # updates the state of the agent
      Agent.update(:update_observer, fn(id_map) -> update_vals(key, id_map, id) end)
    end

    @doc """
    Deletes the given ids of the specified resource
    resource should be a string and one of the following `"gazetteer"`, `"chronontology"`, `"thesuarus"`
    """
    def del_resource_ids(resource, ids) do
      key = get_resource_key(resource) # see above
      Agent.update(:update_observer, fn id_map -> delete_vals(key, id_map, ids) end)
    end

    @doc """
      Returns the current state of the Observer i.e. a Map with MapSets

      Returns `%{spatial: MapSet, temporal: MapSet, subject: MapSet}`
    """
    def get_resource_ids() do
      Agent.get(:update_observer, fn map -> map end)
    end

    @doc """
      Returns the resource ids for the specified resource as a key, value tuple
      keys: are e.g. :spatial, :temporal, :subject etc
      values are stored as a MapSet
      Returns `{:key, MapSet}`
    """
    def get_resources_ids(resource) do
      key = get_resource_key(resource)
      ids = Agent.get(:update_observer, fn map -> map[key] end)
      {key, ids}
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
    @moduledoc """
    The Manager-Module operates on the data stored in the observer. One can use it to find the parent-documents containg the subdocuments with the ids of the recently updated docs
    """

    alias ArgosAggregation.Project

    @headers [{"Content-Type", "application/json"}]

    @base_url "#{Application.get_env(:argos_api, :elasticsearch_url)}/#{Application.get_env(:argos_api, :index_name)}"

    @doc """
    Starts the update process for the given ids.
    One can start the function with a tuple of key and ids as Enumerable or a map of key and ids as Enumerables
    """
    def process_updates({key, ids}) do
      find_relations(key, ids) |> handle_result
    end
    def process_updates(updated_ids) do
      Enum.each(updated_ids, fn(tup) ->
        process_updates(tup)
      end )
    end

    defp find_relations(_filter, [] = _ids) do {:error, nil} end
    defp find_relations(filter, ids) do
      query = get_query(filter, ids)
      "#{@base_url}/_search"
      |> HTTPoison.post(query, @headers)
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
