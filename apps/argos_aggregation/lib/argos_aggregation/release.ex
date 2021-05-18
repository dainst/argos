defmodule ArgosAggregation.Release do
  def seed_projects(date) do
    HTTPoison.start()
    ArgosAggregation.ProjectCLI.run(date)
  end

  def seed_projects() do
    HTTPoison.start()
    ArgosAggregation.ProjectCLI.run()
  end

  def seed_bibliography(date) do
    HTTPoison.start()
    ArgosAggregation.BibliographyCLI.run(date)
  end

  def seed_bibliography() do
    HTTPoison.start()
    ArgosAggregation.BibliographyCLI.run()
  end
end
