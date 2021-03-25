defmodule Argos.Release do
  require Logger
  @elasticsearch_url Application.get_env(:argos, :elasticsearch_url) <> Application.get_env(:argos, :index_path)
  @elasticsearch_mapping_path Application.get_env(:argos, :elasticsearch_mapping_path)

  def seed_projects(date) do
    HTTPoison.start()
    Argos.Data.ProjectCLI.run(date)
  end

  def seed_projects() do
    HTTPoison.start()
    Argos.Data.ProjectCLI.run()
  end

  def update_mapping() do
    HTTPoison.start()
    mapping = File.read!(@elasticsearch_mapping_path)

    clear_index()

    "#{@elasticsearch_url}/_mapping"
    |> HTTPoison.put(mapping, [{"Content-Type", "application/json"}])
    |> IO.inspect
  end


  def clear_index() do
    HTTPoison.start()

    "#{@elasticsearch_url}"
    |> HTTPoison.delete()

    "#{@elasticsearch_url}"
    |> HTTPoison.put()
  end
end
