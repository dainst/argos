defmodule Argos.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Plug.Cowboy, scheme: :http, plug: Argos, options: [port: 4001]}
      # Starts a worker by calling: Argos.Worker.start_link(arg)
      # {Argos.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Argos.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
