defmodule ArgosData.Release do
  def seed_projects(date) do
    HTTPoison.start()
    ArgosData.ProjectCLI.run(date)
  end

  def seed_projects() do
    HTTPoison.start()
    ArgosData.ProjectCLI.run()
  end
end
