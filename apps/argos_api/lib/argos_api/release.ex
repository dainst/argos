defmodule ArgosAPI.Release do
  require Logger

  def update_mapping() do
    HTTPoison.start()
    ArgosAPI.Application.update_mapping()
    |> IO.inspect
  end

  def clear_index() do
    HTTPoison.start()
    ArgosAPI.Application.delete_index()
    |> IO.inspect
  end
end
