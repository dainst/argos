defmodule Argos do
  @moduledoc """
  Documentation for `Argos`.
  """
  import Plug.Conn

  use Plug.Router

  plug :match
  plug :dispatch

  get "/search" do
    send_resp(conn, 200, "Welcome!")
  end

  get "/project/:id" do
    send_resp(conn, 200, "Project: #{id}")
  end

end
