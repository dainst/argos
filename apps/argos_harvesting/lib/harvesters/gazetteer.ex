defmodule ArgosHarvesting.Gazetteer do
  alias ArgosCore.Gazetteer.DataProvider

  require Logger

  def run_harvest(%{last_run: last_run}) do

    last_run
    |> DataProvider.get_by_date()
    |> Stream.map(fn val ->
      case val do
        {:ok, data} ->
          data

        {:error, msg} ->
          Logger.error("Error while harvesting:")
          Logger.error(msg)
          nil
      end
    end)
    |> Stream.reject(fn val -> is_nil(val) end)
  end

  def run_harvest(%{}) do
    DataProvider.get_all()
    |> Stream.map(fn val ->
      case val do
        {:ok, data} ->
          data

        {:error, msg} ->
          Logger.error("Error while harvesting:")
          Logger.error(msg)
          nil
      end
    end)
    |> Stream.reject(fn val -> is_nil(val) end)
  end
end
