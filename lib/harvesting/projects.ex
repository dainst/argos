defmodule Argos.Harvesting.Projects do
  use GenServer

  require Logger
  alias Argos.Harvesting.Gazetteer.GazetteerClient
  alias Argos.Harvesting.Chronontology.ChronontologyClient

  @base_url Application.get_env(:argos, :projects_url)
  @interval Application.get_env(:argos, :projects_harvest_interval)

  @elastic_search Application.get_env(:argos, :elasticsearch_url)

  defp get_timezone() do
    "Etc/UTC"
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

    Logger.info("Starting projects harvester with an interval of #{@interval}ms.")

    Process.send(self(), :run, [])
    {:ok, state}
  end

  def handle_info(:run, state) do # TODO: Übernommen, warum info und nicht cast/call?
    now = DateTime.now!(get_timezone())
    run_harvest(state.last_run)

    state = %{state | last_run: now}
    schedule_next_harvest()
    {:noreply, state}
  end

  defp schedule_next_harvest() do
    Process.send_after(self(), :run, @interval)
  end
  def run_harvest() do
    "#{@base_url}/api/projects"
    |> start
  end

  def run_harvest(%DateTime{} = datetime) do
    query = URI.encode_query(%{ since: DateTime.to_naive(datetime) })

    "#{@base_url}/api/projects?#{query}"
    |> start
  end

  defp start(url) do
    Logger.info("Running projects harvest at #{url}.")
    query_result =
      url
      |> HTTPoison.get
      |> handle_result
    # TODO: Switch to project code after Erga got updated
   query_result["data"]
    |> Enum.map(&denormalize/1)
    |> Enum.each(&upsert/1)

  end

  defp denormalize(proj) do
    rich_res = get_linked_resources(proj["linked_resources"])
    Map.put(proj, "linked_resources", rich_res)
  end

  defp get_linked_resources(resources) when is_list(resources) do
    Enum.map(resources, &get_linked_resources/1)
  end

  defp get_linked_resources(%{"linked_system" => _ } = resource) do
     response = case resource["linked_system"] do
        "Gazetteer" -> "https://gazetteer.dainst.org/place/" <> id = resource["uri"]
                        GazetteerClient.fetch_one!(%{id: id})
        "Chronontology" -> "https://chronontology.dainst.org/period/" <> id = resource["uri"]
                        ChronontologyClient.fetch_one!(%{id: id})

     end
     Map.put(resource, :linked_data, response)
  end

  defp upsert(project) do
    Logger.info("Upserting '#{project["project_key"]}'.")
    body =
      %{
        doc: project,
        doc_as_upsert: true
      }
      |> Poison.encode!

    "#{@elastic_search}/_update/project-#{project["project_key"]}"
    |> HTTPoison.post!(body, [{"Content-Type", "application/json"}])
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}} = _response) do
    Poison.decode!(body)
  end

  defp handle_result({:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}) do
    Logger.warn("No connection")
    exit('no db connection')
  end

  defp handle_result(call) do
    IO.inspect(call)
    Logger.error("Cannot process result: #{call}")
    exit('no db connection')
  end

  # TODO: Handle error results
end
