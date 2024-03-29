defmodule ArgosCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url "#{Application.get_env(:argos_core, :elasticsearch_url)}/#{Application.get_env(:argos_core, :index_name)}"
  @elasticsearch_mapping_path Application.get_env(:argos_core, :elasticsearch_mapping_path, Application.app_dir(:argos_core, "priv/elasticsearch-mapping.json"))

  require Logger
  require Finch
  require Cachex

  def update_mapping() do
    Logger.info("update mapping")
    delete_index()
    put_index()
    put_mapping()
  end

  def put_index() do
    ArgosCore.HTTPClient.put(
      "#{@elasticsearch_url}"
    )
  end

  def delete_index() do
    ArgosCore.HTTPClient.delete(@elasticsearch_url)
  end

  def put_mapping() do
    mapping = File.read!(@elasticsearch_mapping_path)
    ArgosCore.HTTPClient.put_payload(
      "#{@elasticsearch_url}/_mapping",
      [{"Content-Type", "application/json"}],
      mapping
    )
  end

  defp initialize_index() do
    ArgosCore.HTTPClient.get(@elasticsearch_url)
    |> case do
      error when error in [
        {:error, %Mint.TransportError{
          :reason => :closed,
        }},
        {:error, %Mint.TransportError{
          :reason => :econnrefused,
        }}
      ] ->
        delay = 1000 * 5
        Logger.warning("No connection to Elasticsearch at #{@elasticsearch_url}. Rescheduling initialization in #{delay}ms...")
        :timer.sleep(delay)
        initialize_index()

      {:error, %{status: 404, body: body}} ->
        case Poison.decode!(body) do
          %{"error" => %{"root_cause" => [%{"type" => "index_not_found_exception"}]}} ->
            Logger.info("Index not setup at #{@elasticsearch_url}, creating index and putting mapping...")
            put_index()
            put_mapping()
        end
      {:ok, _} ->
        Logger.info("Found Elasticsearch index at #{@elasticsearch_url}.")
    end
  end

  def get_http_user_agent_header() do
    {:ok, vsn} = :application.get_key(:argos_core, :vsn)
    {"User-Agent", "argos-harvesting/#{List.to_string(vsn)}"}
  end

  def start(_type, _args) do

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosCore.Supervisor]
    children = [
      {Finch, name: ArgosFinch},
      {Cachex, name: :argos_core_cache}
    ]

    supervisor_response = Supervisor.start_link(children, opts)

    if Application.get_env(:argos_core, :await_index, true) do
      initialize_index()
    end

    supervisor_response
  end
end
