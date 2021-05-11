defmodule ArgosAPI.Release do
  require Logger

  def update_mapping() do
    HTTPoison.start()
    ArgosAPI.Application.update_mapping()
  end

  def clear_index() do
    HTTPoison.start()
    ArgosAPI.Application.delete_index()
  end
end
