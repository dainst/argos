defmodule ArgosAggregation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"
  @active_harvesters Application.get_env(:argos_aggregation, :active_harvesters)
  @elasticsearch_mapping_path Application.get_env(:argos_aggregation, :elasticsearch_mapping_path)

  require Logger
  require Finch

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
    Finch.build(:put, "#{@elasticsearch_url}")
    |> Finch.request(ArgosFinch)
  end

  def delete_index() do
    Finch.build(:delete, "#{@elasticsearch_url}")
    |> Finch.request(ArgosFinch)
  end


  def put_mapping() do
    mapping = File.read!(@elasticsearch_mapping_path)
    Finch.build(:put, "#{@elasticsearch_url}/_mapping", [{"Content-Type", "application/json"}],mapping)
    |> Finch.request(ArgosFinch)
  end


  defp initialize_index() do
    res =Finch.build(:put, @elasticsearch_url)
    |> Finch.request(ArgosFinch)
    case res do
      error when error in [

        {:error, %Mint.HTTPError{
          :reason => :closed,

        }},
        {:error, %Mint.HTTPError{
          :reason => :econnrefused,

        }}
      ] ->
        delay = 1000 * 5
        Logger.warning("No connection to Elasticsearch at #{@elasticsearch_url}. Rescheduling initialization in #{delay}ms...")
        :timer.sleep(delay)
        initialize_index()

      {:ok, %Finch.Response{body: body, status: 404}} ->
        case Poison.decode!(body) do
          %{"error" => %{"root_cause" => [%{"type" => "index_not_found_exception"}]}} ->
            Logger.info("Index not setup at #{@elasticsearch_url}, creating index and putting mapping...")
            put_index()
            put_mapping()
        end

      {:ok, %Finch.Response{status: 200}} ->
        Logger.info("Found Elasticsearch index at #{@elasticsearch_url}.")
      {:error, %Mint.HTTPError{reason: :nxdomain}} ->
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
    children = [{Finch, name: ArgosFinch}] ++ children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosAggregation.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
