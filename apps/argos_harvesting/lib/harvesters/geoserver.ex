defmodule ArgosHarvesting.Geoserver do
  alias ArgosCore.Geoserver.DataProvider

  require Logger

  def run_harvest(%{}) do
    DataProvider.get_all()
  end
end
