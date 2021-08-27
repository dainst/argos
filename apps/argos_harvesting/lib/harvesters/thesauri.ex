defmodule ArgosHarvesting.Thesauri do
  use GenServer
  alias ArgosCore.ElasticSearch.Indexer
  alias ArgosCore.Thesauri.DataProvider

  require Logger

  @interval Application.get_env(:argos_harvesting, :collections_harvest_interval)
  defp get_timezone() do
    "Etc/UTC"
  end

  def init(state) do
    state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

    Logger.info("Starting thesaurus harvester with an interval of #{@interval}ms.")

    Process.send(self(), :run, [])
    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def handle_info(:run, state) do
    now =
      DateTime.now!(get_timezone())
      |> DateTime.to_date()

    run_harvest(state.last_run)

    state = %{state | last_run: now}
    schedule_next_harvest()
    {:noreply, state}
  end

  defp schedule_next_harvest() do
    Process.send_after(self(), :run, @interval)
  end

  def run_harvest() do
    DataProvider.get_all()
    |> Enum.each(&index_concept/1)
  end

  def run_harvest(%Date{} = date) do
    DataProvider.get_by_date(date)
    |> Enum.each(&index_concept/1)
  end

  defp index_concept({:ok, concept}) do
    Indexer.index(concept)
  end

  defp index_concept({:error, err}) do
    Logger.error(err)
  end

  defp index_concept(error) do
    Logger.error(error)
  end
end
