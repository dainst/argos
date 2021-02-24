defmodule Argos.Release do
  require Logger

  def seed_projects() do
    HTTPoison.start()
    Argos.Data.Project.Harvester.run_harvest()
  end
end
