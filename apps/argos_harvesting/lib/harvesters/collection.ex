defmodule ArgosHarvesting.Collection do
  alias ArgosCore.Collection.DataProvider

  require Logger

  def run_harvest(%{last_run: datetime}) do
    DataProvider.get_by_date(datetime)
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
