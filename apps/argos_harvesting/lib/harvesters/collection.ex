defmodule ArgosHarvesting.Collection do
  alias ArgosCore.Collection.DataProvider

  require Logger

  def run_harvest(%{last_run: datetime}) do
    DataProvider.get_by_date(datetime)
  end

  def run_harvest(%{}) do
    DataProvider.get_all()
  end
end
