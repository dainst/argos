defmodule ArgosHarvesting.Thesauri do
  alias ArgosCore.Thesauri.DataProvider

  require Logger

  def run_harvest(%{last_run: last_run}) do
    last_run
    |> DateTime.to_date()
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

  def run_harvest(_state) do
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
