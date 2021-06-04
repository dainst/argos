defmodule ArgosAPI.Errors do

  import Plug.Conn

  def send(conn, status, msg) do
    send_resp(conn, status, Poison.encode!(%{error: msg}))
    |> halt()
  end
  def send(conn, 500) do
    send_resp(conn, 500, Poison.encode!(%{message: "An internal error occured."}))
    |> halt()
  end
end
