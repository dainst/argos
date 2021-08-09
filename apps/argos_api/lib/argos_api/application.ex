defmodule ArgosAPI.Application do
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

  def start(_type, _args) do

    children =
      if running_script?(System.argv) do
        [] # We do not want to (re)start the harvesters when running exs scripts.
      else
        [
          {Plug.Cowboy, scheme: :http, plug: ArgosAPI.Router, options: [port: 4001]},
          {Finch, name: ArgosAPIFinch}
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
