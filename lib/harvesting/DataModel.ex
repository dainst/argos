defmodule DataModel do
  defmodule TranslatedContent do
    @enforce_keys [:text, :lang]
    defstruct [:text, :lang]
    @type t() :: %__MODULE__{
      text: String,
      lang: String
    }
  end

  defmodule Stakeholder do
    @enforce_keys [:label]
    defstruct [:label, :role, :uri, :type]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      role: String.t(),
      uri: String.t(),
      type: String.t(),
    }
  end

  defmodule Person do
    @enforce_keys [:firstname, :lastname]
    defstruct [:firstname, :lastname, title: "", external_id: ""]
    @type t() :: %__MODULE__{
      firstname: String.t(),
      lastname: String.t(),
      title: String.t(),
      external_id: String.t()
    }
  end

  defmodule Image do
    @enforce_keys [:uri]
    defstruct [:uri, label: ""]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      uri: String.t()
    }
  end

  defmodule ExternalLink do
    @enforce_keys [:uri]
    defstruct [:uri, label: "", role: "data"]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      uri: String.t(),
      role: String.t()
    }
  end


  defmodule Projects do
    @enforce_keys [:id, :title]
    defstruct [:id, :title, description: %{}, doi: "", start_date: nil, end_date: nil, subject: [], spatial: [], temporal: [], images: [], stakeholders: [], external_links: [] ]
    @type t() :: %__MODULE__{
      id: String.t(),
      title: TranslatedContent.t(),
      description: TranslatedContent.t(),
      doi: String.t(),
      start_date: Date.t(),
      end_date: Date.t(),
      subject: [Argos.Data.Thesauri.Concept.t()],
      spatial: [Place.t()],
      temporal: [TemporalConcept.t()],
      stakeholders: [Stakeholder.t()],
      images: [Image.t()]
    }
  end
end
