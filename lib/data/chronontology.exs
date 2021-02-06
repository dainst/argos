require Logger

alias Argos.Data.Chronontology
alias Argos.ElasticSearchIndexer

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
    Argos.Data.Chronontology,DataProvider.get_all()
    |> Enum.each(ElasticSearchIndexer.index())
  end

  def handle_arguments({:ok, %Date{} = date}) do
    date
    |> Argos.Data.Chronontology,DataProvider.get_by_date()
    |> Enum.each(ElasticSearchIndexer.index())
  end

  def handle_arguments({:ok, pid}) do
    pid
    |> Argos.Data.Chronontology,DataProvider.get_by_id(pid)
    |> ElasticSearchIndexer.index()
  end

  def handle_arguments({:error, reason}) do
    Logger.error(reason)
  end
end

System.argv()
|> CLI.parse_arguments
|> CLI.handle_arguments
