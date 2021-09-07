defmodule ArgosHarvesting.BaseHarvester do
  use GenServer

  alias ArgosCore.ElasticSearch.Indexer

  require Logger

  @timezone "Etc/UTC"

  def init(%{source: source} = state) do
    state =
      state
      |> Map.put(:last_run, DateTime.now!(@timezone))

    Logger.info("Starting harvester for #{source}")

    Process.send(self(), :run, [])
    {:ok, state}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def handle_info(:run, %{source: source} = state) do
    state =
      try do
        now = DateTime.now!(@timezone)

        state
        |> source.run_harvest()
        |> Enum.each(&Indexer.index/1)
        # TODO: Indexing in parallel? How to throttle?
        # |> Enum.map(&Task.async(fn -> Indexer.index(&1) end))
        # |> Enum.each(&Task.await/1)

        Map.replace!(state, :last_run, now)
      rescue
        e ->
          Logger.error(e)

          ArgosCore.Mailer.send_email(%{
            subject: "#{source} harvester error:",
            text_body: "#{e.__struct__}\n #{Exception.message(e)}}"
          })

          state
      end

    schedule_next_run(state)
    {:noreply, state}
  end

  defp schedule_next_run(%{interval: interval}) do
    Process.send_after(self(), :run, interval)
  end
end
