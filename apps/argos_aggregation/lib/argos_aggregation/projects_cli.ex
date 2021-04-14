require Logger

defmodule ArgosAggregation.ProjectCLI do

  def run() do
    ArgosAggregation.Project.Harvester.run_harvest()
  end

  def run(date_string) do
    date_string
    |> parse_arguments()
    |> handle_arguments()
  end

  def parse_arguments(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}
      {:error, _} ->
        case Date.from_iso8601(date_string) do
          {:ok, _date} ->
            DateTime.from_iso8601("#{date_string}T00:00:00Z")
          error ->
            error
        end
    end
  end

  def handle_arguments({:ok, date, _offset}) do
    ArgosAggregation.Project.Harvester.run_harvest(date)
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end

end
