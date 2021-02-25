defmodule Argos.API.SearchAggregations do
  require Logger

  def aggregation_definitions() do
    %{
      type: %{terms: %{field: "type" }},
      "spatial.resource.id": %{
        terms: %{field: "spatial.resource.id"},
        aggs: %{
          example_doc: %{
            top_hits: %{
              size: 1,
              _source: %{
                include: ["spatial.resource"]
              }
            }
          }
        }
      },
      "temporal.resource.id": %{
        terms: %{field: "temporal.resource.id" },
        aggs: %{
          example_doc: %{
            top_hits: %{
              size: 1,
              _source: %{
                include: ["temporal.resource"]
              }
            }
          }
        }
      },
      "subject.resource.id": %{
        terms: %{field: "subject.resource.id"},
        aggs: %{
          example_doc: %{
            top_hits: %{
              size: 1,
              _source: %{
                include: ["subject.resource"]
              }
            }
          }
        }
      },
      "stakeholders.uri": %{
        terms: %{field: "stakeholders.uri"},
        aggs: %{
          example_doc: %{
            top_hits: %{
              size: 1,
              _source: %{
                include: ["stakeholders"]
              }
            }
          }
        }
      }
    }
  end

  def transform_aggregations(aggregations) do
    aggregations
    |> Enum.map(fn ({name, content}) ->
      values =
        content["buckets"]
        |> Enum.map(&transform_aggregation_bucket(name, &1))
      %{
        key: name,
        values: values
      }
    end)
  end

  defp transform_aggregation_bucket(
    aggregation_name,
    %{
      "doc_count" => count,
      "key" => key,
      "example_doc" => %{
        "hits" => %{
          "hits" => [
            %{"_source" => example}
          ]
        }
      }
    }) do
      values_by_example(aggregation_name, count, key, example)
  end
  defp transform_aggregation_bucket(
    _name,
    %{"doc_count" => count, "key" => key}
    ) do
    %{
      key: key,
      count: count
    }
  end

  defp values_by_example("spatial.resource.id", count, id, %{"spatial" => resource_list}) do
    place =
      resource_list
      |> Enum.map(fn (%{"resource" => place}) ->
        place
      end)
      |> Enum.filter(fn(place) ->
        place["id"] == id
      end)
      |> List.first()

    %{key: id, count: count, labels: place["label"]}
  end

  defp values_by_example("subject.resource.id", count, id, %{"subject" => resource_list}) do
    concept =
      resource_list
      |> Enum.map(fn (%{"resource" => concept}) ->
        concept
      end)
      |> Enum.filter(fn(concept) ->
        concept["id"] == id
      end)
      |> List.first()

    %{key: id, count: count, labels: concept["label"]}
  end

  defp values_by_example("temporal.resource.id", count, id, %{"temporal" => resource_list}) do
    temporal_concept =
      resource_list
      |> Enum.map(fn (%{"resource" => temporal_concept}) ->
        temporal_concept
      end)
      |> Enum.filter(fn(temporal_concept) ->
        temporal_concept["id"] == id
      end)
      |> List.first()

    %{key: id, count: count, labels: temporal_concept["label"]}
  end

  defp values_by_example("stakeholders.uri", count, uri, %{"stakeholders" => stakeholders}) do
    stakeholder =
      stakeholders
      |> Enum.filter(fn(stakeholder) ->
        stakeholder["uri"] == uri
      end)
      |> List.first()

    %{key: uri, count: count, labels: stakeholder["label"]}
  end

  defp values_by_example(aggregation_name, _count, _key, example) do
    Logger.warning("Unknown aggregation name or example while trying to create value:#{aggregation_name}. Example provided:")
    Logger.warning(example)
  end
end
