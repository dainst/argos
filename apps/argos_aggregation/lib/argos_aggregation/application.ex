defmodule ArgosAggregation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @active_harvesters Application.get_env(:argos_aggregation, :active_harvesters)
  @elasticsearch_mapping_path Application.get_env(:argos_aggregation, :elasticsearch_mapping_path)

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
    Logger.info("update mapping")
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
      {:error, %HTTPoison.Error{id: nil, reason: :nxdomain}} ->
        Logger.error("nxdomain error")
        raise "nxdomain"
    end
  end

  def get_http_user_agent_header() do
    {:ok, vsn} = :application.get_key(:argos_aggregation, :vsn)
    {"User-Agent", "Argos-Aggregation/#{List.to_string(vsn)}"}
  end

  def start(_type, _args) do
    if Application.get_env(:argos_aggregation, :await_index, true) do
      initialize_index()
    end

    children =
      if running_script?(System.argv) do
        [] # We do not want to (re)start the harvesters when running exs scripts.
      else
        @active_harvesters
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosAggregation.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
