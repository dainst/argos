defmodule Argos.Data.GenericDataProvider do
  @callback get_all() :: [any]
  @callback get_by_id(id::any) :: any | {:error, :not_implemented}
  @callback get_by_date(date::Date.t()) :: [any] | {:error, :not_implemented}
end

defmodule Argos.Data.TranslatedContent do
  @enforce_keys [:text, :lang]
  defstruct [:text, :lang]
  @type t() :: %__MODULE__{
    text: String,
    lang: String
  }
end
