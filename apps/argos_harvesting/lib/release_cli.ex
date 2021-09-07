defmodule ArgosHarvesting.ReleaseCLI do
  require Logger

  alias ArgosHarvesting.{
    Bibliography,
    Chronontology,
    Collection,
    Gazetteer,
    Thesauri
  }

  alias ArgosCore.ElasticSearch.Indexer

  def seed(source) do
    seed(source, nil)
  end

  def seed(source, since) do
    case source do
      "all" ->
        run_harvest(Bibliography, since)
        run_harvest(Chronontology, since)
        run_harvest(Collection, since)
        run_harvest(Gazetteer, since)
        run_harvest(Thesauri, since)
      "bibliography" ->
        run_harvest(Bibliography, since)
      "chronontology" ->
        run_harvest(Chronontology, since)
      "collection" ->
        run_harvest(Collection, since)
      "gazetteer" ->
        run_harvest(Gazetteer, since)
      "thesauri" ->
        run_harvest(Thesauri, since)
    end
  end

  defp run_harvest(source, date) do
    Application.ensure_all_started(:argos_core)

    case date do
      nil ->
        source.run_harvest(%{})
      date ->
        date
        |> Date.from_iso8601()
        |> case do
          {:ok, result} ->
            source.run_harvest(%{last_run: result})
          error ->
            error
        end
    end
    |> Stream.map(fn val ->
      case val do
        {:error, msg} ->
          Logger.error("Error while harvesting:")
          Logger.error(msg)
          nil
        data ->
          data
      end
    end)
    |> Stream.reject(fn val -> is_nil(val) end)
    |> Enum.each(&Indexer.index/1)
  end
end
