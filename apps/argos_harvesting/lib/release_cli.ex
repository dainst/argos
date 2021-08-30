defmodule ArgosHarvesting.ReleaseCLI do
  def seed_collections(date) do
    Application.ensure_all_started(:argos_core)
    ArgosHarvesting.CollectionCLI.run(date)
  end

  def seed_collections() do
    Application.ensure_all_started(:argos_core)
    ArgosHarvesting.CollectionCLI.run()
  end

  def seed_bibliography(date) do
    Application.ensure_all_started(:argos_core)
    ArgosHarvesting.BibliographyCLI.run(date)
  end

  def seed_bibliography() do
    Application.ensure_all_started(:argos_core)
    ArgosHarvesting.BibliographyCLI.run()
  end
end
