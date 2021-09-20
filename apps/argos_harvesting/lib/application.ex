defmodule ArgosHarvesting.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

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

  defp get_harvesters() do
    [
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Bibliography,
            interval: Application.get_env(:argos_harvesting, :bibliography_harvest_interval)
          }
        },
        id: :bibliography
      ),
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Chronontology,
            interval: Application.get_env(:argos_harvesting, :chronontology_harvest_interval)
          }
        },
        id: :chronontology
      ),
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Collection,
            interval: Application.get_env(:argos_harvesting, :collections_harvest_interval)
          }
        },
        id: :collection
      ),
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Gazetteer,
            interval: Application.get_env(:argos_harvesting, :gazetteer_harvest_interval)
          }
        },
        id: :gazetteer
      ),
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Geoserver,
            interval: Application.get_env(:argos_harvesting, :geoserver_harvest_interval)
          }
        },
        id: :geoserver
      ),
      Supervisor.child_spec(
        {
          ArgosHarvesting.BaseHarvester,
          %{
            source: ArgosHarvesting.Thesauri,
            interval: Application.get_env(:argos_harvesting, :thesauri_harvest_interval)
          }
        },
        id: :thesauri
      )
    ]
  end

  def start(_type, _args) do
    children =
      if running_script?(System.argv()) do
        # We do not want to (re)start the harvesters when running exs scripts.
        []
      else
        get_harvesters()
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArgosHarvesting.Supervisor]

    if children != [] do
      Logger.info("Starting harvesters...")
    end

    Supervisor.start_link(children, opts)
  end
end
