defmodule ArgosAPI.PublicFilesPlug do
  @doc """
  Servers static files found in priv/public.
  """
  use Plug.Builder
  alias ArgosAPI.Errors

  plug Plug.Static, at: "/", from: {:argos_api, "priv/public"}
  plug :not_found

  def not_found(conn, _) do
    Errors.send(conn, 404, "Requested resource not found!")
  end
end
