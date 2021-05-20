defmodule ArgosAggregation.AbstractDataProvider do
  @callback get_all() :: [any]
  @callback get_by_id(id::any) :: any | {:error, :not_implemented}
  @callback get_by_date(date::Date.t()) :: [any] | {:error, :not_implemented}
  @callback get_by_date(date::DateTime.t()) :: [any] | {:error, :not_implemented}
end

defmodule ArgosAggregation.TranslatedContent do
  @enforce_keys [:text, :lang]
  defstruct [:text, :lang]
  @type t() :: %__MODULE__{
    text: String,
    lang: String
  }

  def from_map(%{"text" => t, "lang" => l}) do
    %ArgosAggregation.TranslatedContent{
      text: t,
      lang: l
    }
  end
end
