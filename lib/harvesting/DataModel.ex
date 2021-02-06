defmodule DataModel do
  defmodule TranslatedContent do
    @enforce_keys [:text, :lang]
    defstruct [:text, :lang]
    @type t() :: %__MODULE__{
      text: String,
      lang: String
    }
  end
end
