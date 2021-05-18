defmodule ArgosAggregation.AbstractDataProvider do
  @callback get_all() :: Stream
  @callback get_by_id(id::any) :: any | {:error, :not_implemented}
  @callback get_by_date(date::Date.t()) :: Stream | {:error, :not_implemented}
  @callback get_by_date(date::DateTime.t()) :: Stream | {:error, :not_implemented}
end

defmodule ArgosAggregation.TranslatedContent do
  @enforce_keys [:text, :lang]
  defstruct [:text, :lang]
  @type t() :: %__MODULE__{
    text: String,
    lang: String
  }

  def create_translated_content(%{"text" => t, "lang" => l}) do
    %ArgosAggregation.TranslatedContent{
      text: t,
      lang: l
    }
  end

  def create_tc_list(nil), do: []
  def create_tc_list([]), do: []
  def create_tc_list(data) do
    for t <- data do create_translated_content(t) end
  end
end
