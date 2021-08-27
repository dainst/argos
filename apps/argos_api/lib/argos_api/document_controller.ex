defmodule ArgosAPI.DocumentController do
  import Plug.Conn

  alias ArgosAPI.Errors

  def get(conn) do

    id = Map.get(conn.params, "id")

    case ArgosAggregation.ElasticSearch.DataProvider.get_doc(id) do
      {:ok, doc} ->
        send_resp(conn, 200, Poison.encode!(doc))
      {:error, 404} ->
        Errors.send(conn, 404, "Document #{id} not found.")
        {:error, _} ->
          Errors.send(conn, 500)
    end
  end
end
