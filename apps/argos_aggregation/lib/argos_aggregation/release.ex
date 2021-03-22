defmodule ArgosAggregation.Release do
  def seed_projects(date) do
    HTTPoison.start()
    ArgosAggregation.ProjectCLI.run(date)
  end

  def seed_projects() do
    HTTPoison.start()
    ArgosAggregation.ProjectCLI.run()
  end
end
