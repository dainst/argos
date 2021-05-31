defmodule ArgosAggregation.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key false
    end
  end
end

defmodule ArgosAggregation.CoreFields do

  use ArgosAggregation.Schema

  alias ArgosAggregation.TranslatedContent
  alias ArgosAggregation.Gazetteer.Place

  import Ecto.Changeset

  embedded_schema do
    field :source_id, :string
    field :type, Ecto.Enum, values: [:place, :concept, :project, :bibliographic_record]
    field :uri, :string
    embeds_many :title, TranslatedContent
    embeds_many :spatial, Place
    embeds_many :is_a, Concept
  end

  def changeset(fields, params \\ %{}) do
    fields
    |> cast(params, [:source_id, :type, :uri])
    |> cast_embed(:title, [:required])
    |> cast_embed(:spatial)
    |> validate_required([:source_id, :type, :uri])
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
