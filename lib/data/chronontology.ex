defmodule Argos.Data.Chronontology do

  defmodule TemporalConcept do
    alias DataModel.TranslatedContent

    @enforce_keys [:uri, :label, :begin, :end]
    defstruct [:uri, :label, :begin, :end]
    @type t() :: %__MODULE__{
      uri: String.t(),
      label: TranslatedContent.t(),
      begin: integer(),
      end: integer()
    }
  end

  defmodule DataProvider do
    @behaviour Argos.Data.GenericProvider
    @base_url Application.get_env(:argos, :chronontology_url)

    alias DataModel.TranslatedContent

    @impl Argos.Data.GenericProvider
    def get_all() do
      []
    end

    @impl Argos.Data.GenericProvider
    def get_by_id(id) do
      nil
    end

    @impl Argos.Data.GenericProvider
    def get_by_date(%NaiveDateTime{} = _date) do
      []
    end
  end
end
