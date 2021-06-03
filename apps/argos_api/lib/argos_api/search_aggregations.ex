defmodule ArgosAPI.SearchAggregations do
  require Logger

  def aggregation_definitions() do
    %{
      general_topic_id: create_topic_aggregation_definition("general_topic"),
      spatial_topic_id: create_topic_aggregation_definition("spatial_topic"),
      temporal_topic_id: create_topic_aggregation_definition("temporal_topic"),
      type: %{terms: %{field: "type" }},
    }
  end

  defp create_topic_aggregation_definition(type) do
    %{
      terms: %{field: "core_fields.#{type}s.resource.core_fields.id"},
      aggs: %{
        example_doc: %{
          top_hits: %{
            size: 1,
            _source: %{
              include: ["core_fields.#{type}s.resource"]
            }
          }
        }
      }
    }
  end

  def reshape_search_result_aggregations(aggregations) do
    aggregations
    |> Enum.map(fn ({name, content}) ->
      values =
        content["buckets"]
        |> Enum.map(&reshape_aggregation_bucket(name, &1))
      %{
        key: name,
        values: values
      }
    end)
  end

  defp reshape_aggregation_bucket(
    aggregation_name,
    %{
      "doc_count" => count,
      "key" => key,
      "example_doc" => %{
        "hits" => %{
          "hits" => [
            %{"_source" => example_doc_containing_aggregation}
          ]
        }
      }
    }) do
      reshape_bucket_values_by_example(aggregation_name, count, key, example_doc_containing_aggregation)
  end
  defp reshape_aggregation_bucket(
    _name,
    %{"doc_count" => count, "key" => key}
    ) do
    %{ key: key, count: count, label: []}
  end


  defp reshape_bucket_values_by_example("general_topic_id", count, id, %{"core_fields" => %{"general_topics" => topics_in_example}}) do
    %{key: id, count: count, label: create_topic_label_by_example(id, topics_in_example)}
  end
  defp reshape_bucket_values_by_example("spatial_topic_id", count, id, %{"core_fields" => %{"spatial_topics" => topics_in_example}}) do
    %{key: id, count: count, label: create_topic_label_by_example(id, topics_in_example)}
  end
  defp reshape_bucket_values_by_example("temporal_topic_id", count, id, %{"core_fields" => %{"temporal_topics" => topics_in_example}}) do
    %{key: id, count: count, label: create_topic_label_by_example(id, topics_in_example)}
  end

  defp create_topic_label_by_example(id, topics_in_example) do
    topic =
      topics_in_example
      |> Enum.map(fn (%{"resource" => topic }) ->
        topic
      end)
      |> Enum.filter(fn(topic) ->
        topic["core_fields"]["id"] == id
      end)
      |> List.first()

      topic["core_fields"]["title"]
  end
end
