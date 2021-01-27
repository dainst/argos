require Logger

defmodule CLI do
  def parse_arguments(["--script"]) do
    {:ok}
  end

  def parse_arguments(["--script", "pid=" <> pid]) do
    {:ok, pid}
  end

  def parse_arguments(["--script", "date=" <> date_string]) do
    Date.from_iso8601(date_string)
  end

  def handle_arguments({:ok}) do
    Argos.Harvesting.Chronontology.run_harvest(Date.utc_today())
  end

  def handle_arguments({:ok, %Date{} = date}) do
    Argos.Harvesting.Chronontology.run_harvest(date)
  end

  def handle_arguments({:ok, pid}) do
    Argos.Harvesting.Chronontology.ChronontologyClient.fetch_by_id!(%{id: pid})
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end
end

System.argv()
|> CLI.parse_arguments
|> CLI.handle_arguments
