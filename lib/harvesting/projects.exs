require Logger

defmodule CLI do
  def parse_arguments(["--script"]) do
    {:ok}
  end

  def parse_arguments(["--script", date_string]) do
    case DateTime.from_iso8601(date_string) do
      {:ok, _datetime} = result ->
        result
      {:error, :invalid_format} ->
        case Date.from_iso8601(date_string) do
          {:ok, _date} ->
            DateTime.from_iso8601("#{date_string}T00:00:00Z")
          error ->
            error
        end
    end
  end

  def handle_arguments({:ok}) do
    Argos.Data.Project.Harvester.run_harvest()
  end

  def handle_arguments({:ok, date, _offset}) do
    Argos.Data.Project.Harvester.run_harvest(date)
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end

end

System.argv
|> CLI.parse_arguments
|> CLI.handle_arguments
