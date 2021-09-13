defmodule ArgosHarvesting.Chronontology do
  alias ArgosCore.Chronontology.DataProvider

  require Logger

  def run_harvest(%{last_run: %DateTime{} = datetime}) do
    DataProvider.get_by_date(datetime)
  end

  def run_harvest(%{}) do
    DataProvider.get_all()
  end
end
