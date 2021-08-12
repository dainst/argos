defmodule ArgosAggregation.Release do
  def seed_collections(date) do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.CollectionCLI.run(date)
  end

  def seed_collections() do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.CollectionCLI.run()
  end

  def seed_bibliography(date) do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.BibliographyCLI.run(date)
  end

  def seed_bibliography() do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.BibliographyCLI.run()
  end

  def update_mapping() do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.Application.update_mapping()
  end

  def clear_index() do
    Application.ensure_all_started(:argos_aggregation)
    ArgosAggregation.Application.delete_index()
  end
end
