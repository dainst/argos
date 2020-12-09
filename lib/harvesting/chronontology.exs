require Logger

defmodule CLI do
  def parse_arguments(["--script"]) do
    {:ok}
  end

  def parse_arguments(["--script", date_string]) do
    Date.from_iso8601(date_string)
  end

  def handle_arguments({:ok}) do
    Argos.Harvesting.Chronontology.run_harvest(Date.utc_today())
  end

  def handle_arguments({:ok, date}) do
    Argos.Harvesting.Chronontology.run_harvest(date)
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end
end

System.argv()
|> CLI.parse_arguments()
|> CLI.handle_arguments()
