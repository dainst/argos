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

        error_msg =
          state
          |> source.run_harvest()
          |> Stream.map(fn (element) ->
            case element do
              {:ok, doc} ->
                Indexer.index(doc)
              error ->
                error
            end
          end)
          |> Stream.filter(fn(element) ->
            case element do
              {:error, _} ->
                true
              _ ->
                false
            end
          end)
          |> Enum.reduce("", fn(element, acc) ->
            "#{acc}\n#{inspect(element)}"
          end)

        if error_msg != "" do
          ArgosCore.Mailer.send_email(%{
            subject: "#{source} harvester error(s)",
            text_body: error_msg
          })
        end

        Map.replace!(state, :last_run, now)
      rescue
        e ->
          Logger.error(e)

          ArgosCore.Mailer.send_email(%{
            subject: "#{source} harvester error",
            text_body: "#{e.__struct__}\n#{inspect(e)}\n\nRescheduling for previous DateTime: #{inspect(Map.get(state, :last_run))}"
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
