defmodule ArgosHarvesting.Chronontology do
  use GenServer
  alias ArgosCore.ElasticSearch.Indexer

  require Logger

  @interval Application.get_env(:argos_harvesting, :temporal_concepts_harvest_interval)
  defp get_timezone() do
    "Etc/UTC"
  end

  def init(state) do
    state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

    Logger.info("Starting chronontology harvester with an interval of #{@interval}ms.")

    Process.send(self(), :run, [])
    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  # TODO: Übernommen, warum info und nicht cast/call?
  def handle_info(:run, state) do
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
    DataProvider.get_all()
    |> Stream.map(fn val ->
      case val do
        {:ok, data} ->
          data

        {:error, msg} ->
          Logger.error("Error while harvesting:")
          Logger.error(msg)
          nil
      end
    end)
    |> Stream.reject(fn val -> is_nil(val) end)
    |> Enum.each(&Indexer.index/1)
  end

  def run_harvest(%DateTime{} = datetime) do
    DataProvider.get_by_date(datetime)
    |> Stream.map(fn val ->
      case val do
        {:ok, data} ->
          data

        {:error, msg} ->
          Logger.error("Error while harvesting:")
          Logger.error(msg)
          nil
      end
    end)
    |> Stream.reject(fn val -> is_nil(val) end)
    |> Enum.each(&Indexer.index/1)
  end
end
