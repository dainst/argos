defmodule ArgosAggregation.Release do
  def seed_collections(date) do
    ArgosAggregation.CollectionCLI.run(date)
  end

  def seed_collections() do
    ArgosAggregation.CollectionCLI.run()
  end

  def seed_bibliography(date) do
    ArgosAggregation.BibliographyCLI.run(date)
  end

  def seed_bibliography() do
    ArgosAggregation.BibliographyCLI.run()
  end

  def update_mapping() do
    ArgosAggregation.Application.update_mapping()
  end

  def clear_index() do
    ArgosAggregation.Application.delete_index()
  end
end
