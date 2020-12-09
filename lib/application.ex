defmodule Argos.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  defp running_script?([head]) do
    head == "--script"
  end

  defp running_script?([head | _tail]) do
    head == "--script"
  end

  defp running_script?(_) do
    false
  end

  def start(_type, _args) do
    children =
      if running_script?(System.argv) do
        [] # We do not want to (re)start the application (harvestes + cowboy webserver) when running exs scripts.
      else
        [
          {Plug.Cowboy, scheme: :http, plug: Argos.API.Router, options: [port: 4001]},
          Argos.Harvesting.Chronontology,
          Argos.Harvesting.Projects
          # Starts a worker by calling: Argos.Worker.start_link(arg)
          # {Argos.Worker, arg}
        ]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Argos.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
