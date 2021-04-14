defmodule ArgosAggregation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url Application.get_env(:argos_api, :elasticsearch_url)

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

  defp await_index() do
    delay = 1000 * 30

    case HTTPoison.get(@elasticsearch_url) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Found Elasticsearch index at #{@elasticsearch_url}.")
        :ok
      _ ->
        Logger.info("Waiting for Elasticsearch index at #{@elasticsearch_url}.")
        :timer.sleep(delay)
        await_index()
    end
  end

  def start(_type, _args) do
    children =
      if running_script?(System.argv) do
        [] # We do not want to (re)start the harvesters when running exs scripts.
      else
        [
          ArgosAggregation.Project.Harvester
        ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosAggregation.Supervisor]

    await_index()

    Supervisor.start_link(children, opts)
  end
end
