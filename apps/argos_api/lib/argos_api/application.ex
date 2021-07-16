defmodule ArgosAPI.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @elasticsearch_url "#{Application.get_env(:argos_aggregation, :elasticsearch_url)}/#{Application.get_env(:argos_aggregation, :index_name)}"

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
    res = Finch.build(:get, "#{@elasticsearch_url}")
    |> Finch.request(ArgosAPIFinch)
    case res do
      {:ok, %Finch.Response{status: 200}} ->
        Logger.info("Found Elasticsearch index at #{@elasticsearch_url}.")
        :ok
      _ ->
        Logger.info("Waiting for Elasticsearch index at #{@elasticsearch_url}.")
        :timer.sleep(delay)
        await_index()
    end
  end

  def start(_type, _args) do
    Finch.start_link(name: ArgosAPIFinch)
    if Application.get_env(:argos_api, :await_index, true) do
      await_index()
    end

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
