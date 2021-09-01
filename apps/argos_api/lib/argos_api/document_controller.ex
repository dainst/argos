defmodule ArgosAPI.DocumentController do
  import Plug.Conn

  alias ArgosAPI.Errors

  def get(conn) do

    id = Map.get(conn.params, "id")

    case ArgosCore.ElasticSearch.DataProvider.get_doc(id) do
      {:ok, doc} ->
        send_resp(conn, 200, Poison.encode!(doc))
      {:error, %{status: 404}} ->
        Errors.send(conn, 404, "Document #{id} not found.")
    end
  end
end
