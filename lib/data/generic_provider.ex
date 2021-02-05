defmodule Argos.Data.GenericProvider do
  @callback get_all() :: [any]
  @callback get_by_id(id::any) :: any | {:error, :not_implemented}
  @callback get_by_date(date::NaiveDateTime.t()) :: [any] | {:error, :not_implemented}
end
