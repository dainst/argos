defmodule ArgosAggregation.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key false
    end
  end
end


defmodule ArgosAggregation.TranslatedContent do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    field :lang, :string, default: ""
    field :text, :string
  end

  def changeset(translated_content, params \\ %{}) do
    translated_content
    |> cast(params, [:lang, :text])
    |> validate_required([:text])
  end
end

defmodule ArgosAggregation.CoreFields do

  use ArgosAggregation.Schema

  alias ArgosAggregation.TranslatedContent
  alias ArgosAggregation.Gazetteer.Place
  alias ArgosAggregation.Thesauri.Concept
  alias ArgosAggregation.Chronontology.TemporalConcept

  import Ecto.Changeset

  embedded_schema do
    field :source_id, :string
    field :type, Ecto.Enum, values: [:place, :concept, :temporal_concept, :project, :bibliographic_record]
    field :uri, :string
    embeds_many :title, TranslatedContent
    embeds_many :description, TranslatedContent
    embeds_many :spatial, Place
    embeds_many :is_a, Concept
    embeds_many :temporal, TemporalConcept
  end

  def changeset(fields, params \\ %{}) do
    fields
    |> cast(params, [:source_id, :type, :uri])
    |> cast_embed(:title, [:required])
    |> cast_embed(:description)
    |> cast_embed(:spatial)
    |> cast_embed(:is_a)
    |> cast_embed(:temporal)
    |> validate_required([:source_id, :type, :uri])
  end
end

defmodule ArgosAggregation.ExternalLink do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    embeds_many :label, TranslatedContent
    field :type, Ecto.Enum, values: [:image, :website]
  end

  def changeset(content, params \\ %{}) do
    content
    |> cast(params, [:type])
    |> cast_embed(:label, [:required])
    |> validate_required([:type])
  end
end
