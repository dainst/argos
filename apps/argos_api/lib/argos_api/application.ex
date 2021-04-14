defmodule ArgosAPI.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url Application.get_env(:argos_api, :elasticsearch_url)
  @elasticsearch_mapping_path Application.get_env(:argos_api, :elasticsearch_mapping_path)

  require Logger

  defp running_script?([head]) do
    head == "--script"
  end

  defp running_script?([head | _tail]) do
    head == "--script"
  end

  defp running_script?(_) do
    false
  end

  def update_mapping() do
    delete_index()
    put_index()
    put_mapping()
  end

  def put_index() do
    "#{@elasticsearch_url}"
    |> HTTPoison.put()
  end

  def delete_index() do
    "#{@elasticsearch_url}"
    |> HTTPoison.delete()
  end


  def put_mapping() do
    mapping = File.read!(@elasticsearch_mapping_path)

    "#{@elasticsearch_url}/_mapping"
    |> HTTPoison.put(mapping, [{"Content-Type", "application/json"}])
  end


  defp initialize_index() do

    case HTTPoison.get(@elasticsearch_url) do
      error when error in [
        {:error, %HTTPoison.Error{id: nil, reason: :closed}},
        {:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}
      ] ->
        delay = 1000 * 5
        Logger.warning("No connection to Elasticsearch at #{@elasticsearch_url}. Rescheduling initialization in #{delay}ms...")
        :timer.sleep(delay)
        initialize_index()

      {:ok, %HTTPoison.Response{body: body, status_code: 404}} ->
        case Poison.decode!(body) do
          %{"error" => %{"root_cause" => [%{"type" => "index_not_found_exception"}]}} ->
            Logger.info("Index not setup at #{@elasticsearch_url}, creating index and putting mapping...")
            put_index()
            put_mapping()
        end

      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Found Elasticsearch index at #{@elasticsearch_url}.")
    end
  end

  def start(_type, _args) do

    initialize_index()

    children =
      if running_script?(System.argv) do
        [] # We do not want to (re)start the harvesters when running exs scripts.
      else
        [
          {Plug.Cowboy, scheme: :http, plug: ArgosAPI.Router, options: [port: 4001]}
        ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosAPI.Supervisor]

    if children != [] do
      Logger.info("Starting server...")
    end

    Supervisor.start_link(children, opts)
  end
end
