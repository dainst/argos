defmodule Argos.Harvesting.Projects do
  use GenServer

  require Logger


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
    |> Enum.map(&get_details(&1["id"]))
    |> Enum.each(&upsert(&1["data"]))
  end

  defp get_details(id) do
    "#{@base_url}/api/projects/#{id}"
      |> HTTPoison.get
      |> handle_result
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

  # TODO: Handle error results
end