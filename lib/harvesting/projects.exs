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
        parse_arguments("#{date_string}T00:00:00Z")
    end
  end

  def parse_arguments(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, _date} = result -> result
      error -> error
    end
  end

  def handle_arguments({:ok}) do
    Argos.Harvesting.Projects.run_harvest()
  end

  def handle_arguments({:ok, date, _offset}) do
    Argos.Harvesting.Projects.run_harvest(date)
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end

end

System.argv
|> CLI.parse_arguments
|> CLI.handle_arguments
