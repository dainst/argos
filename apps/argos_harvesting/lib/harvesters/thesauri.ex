defmodule ArgosHarvesting.Thesauri do
  alias ArgosCore.Thesauri.DataProvider

  require Logger

  def run_harvest(%{last_run: last_run}) do
    last_run
    |> DateTime.to_date()
    |> DataProvider.get_by_date()
  end

  def run_harvest(%{}) do
    DataProvider.get_all()
  end
end
