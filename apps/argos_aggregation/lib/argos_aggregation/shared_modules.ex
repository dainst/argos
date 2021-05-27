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
