require Logger

defmodule CLI do
  def parse_arguments(["--script"]) do
    {:ok}
  end

  def parse_arguments(["--script", "gid=" <> gid ]) do
    {:ok, String.to_integer(gid)}
  end

  def parse_arguments(["--script", "date=" <> date_string]) do
    Date.from_iso8601(date_string)
  end

  def handle_arguments({:ok}) do
    Argos.Harvesting.Gazetteer.run_harvest(Date.utc_today())
  end

  def handle_arguments({:ok, gid}) when is_integer(gid) do
    Argos.Harvesting.Gazetteer.GazetteerClient.fetch_by_id!(%{id: gid})
  end

  def handle_arguments({:ok, date}) do
    Argos.Harvesting.Gazetteer.run_harvest(date)
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end
end

System.argv()
|> CLI.parse_arguments()
|> CLI.handle_arguments()
