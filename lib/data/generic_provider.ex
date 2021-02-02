defmodule Argos.Data.GenericProvider do
  @callback get_by_id(id::any) :: any
  @callback search(query::any) :: [any]
end
