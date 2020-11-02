defmodule Argos.Harvesting.Projects do
  @base_url Application.get_env(:argos, :projects_url)
  @elastic_search Application.get_env(:argos, :elasticsearch_url)

  def start() do
    "#{@base_url}/api/projects"
    |> run_harvest
  end

  def start(%DateTime{} = datetime) do
    query = URI.encode_query(%{ since: datetime })

    "#{@base_url}/api/projects?#{query}"
    |> run_harvest
  end

  defp run_harvest(url) do
    query_result =
      url
      |> HTTPoison.get
      |> handle_result

    # TODO: Switch to project code after Erga got updated
    query_result["data"]
    |> Enum.map(&get_details(&1["id"]))
    |> Enum.each(&put_project(&1))
  end

  defp get_details(id) do
    "#{@base_url}/api/projects/#{id}"
      |> HTTPoison.get
      |> handle_result
  end

  defp put_project(project) do
    "#{@elastic_search}/_doc/project-#{project["project_key"]}"
    |> HTTPoison.put!(Poison.encode!(project), [{"Content-Type", "application/json"}])
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}} = _response) do
    Poison.decode!(body)
  end

  # TODO: Handle error results
end
