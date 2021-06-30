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

  def update_mapping() do
    HTTPoison.start()
    ArgosAggregation.Application.update_mapping()
  end

  def clear_index() do
    HTTPoison.start()
    ArgosAggregation.Application.delete_index()
  end
end
