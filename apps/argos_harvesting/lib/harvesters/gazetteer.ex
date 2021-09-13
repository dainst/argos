defmodule ArgosHarvesting.Gazetteer do
  alias ArgosCore.Gazetteer.DataProvider

  require Logger

  def run_harvest(%{last_run: last_run}) do

    last_run
    |> DataProvider.get_by_date()
  end

  def run_harvest(%{}) do
    DataProvider.get_all()
  end
end
