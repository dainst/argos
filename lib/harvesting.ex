defmodule Argos.Harvesting do
  use GenServer

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    start_harvesters()
    {:ok, state}
  end

  def handle_info(:run, state) do # TODO: Übernommen, warum info und nicht cast/call?
    start_harvesters()
    # IO.puts("Test")
    {:noreply, state}
  end

  defp start_harvesters() do
    Process.send_after(self(), :run, 5 * 1000) # 5 seconds
  end

end
