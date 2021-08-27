defmodule ArgosCore.Release do
  def update_mapping() do
    Application.ensure_all_started(:argos_core)
    ArgosCore.Application.update_mapping()
  end

  def clear_index() do
    Application.ensure_all_started(:argos_core)
    ArgosCore.Application.delete_index()
  end
end
