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

  alias ArgosAggregation.{
    TranslatedContent,
    Person,
    Organisation,
    ExternalLink
  }

  alias ArgosAggregation.SpatialTopic
  alias ArgosAggregation.GeneralTopic
  alias ArgosAggregation.TemporalTopic

  import Ecto.Changeset

  embedded_schema do
    field :id, :string
    field :source_id, :string
    field :type, Ecto.Enum, values: [:place, :concept, :temporal_concept, :project, :biblio]
    field :uri, :string
    embeds_many :title, TranslatedContent
    embeds_many :description, TranslatedContent
    embeds_many :spatial_topics, SpatialTopic
    embeds_many :general_topics, GeneralTopic
    embeds_many :temporal_topics, TemporalTopic
    embeds_many :persons, Person
    embeds_many :organisations, Organisation
    embeds_many :external_links, ExternalLink
  end

  def changeset(fields, params \\ %{}) do
    fields
    |> cast(params, [:source_id, :type, :uri])
    |> create_id()
    |> cast_embed(:title, [required: true])
    |> cast_embed(:description)
    |> cast_embed(:spatial_topics)
    |> cast_embed(:general_topics)
    |> cast_embed(:temporal_topics)
    |> cast_embed(:persons)
    |> cast_embed(:organisations)
    |> cast_embed(:external_links)
    |> validate_required([:source_id, :type, :uri])
  end

  defp create_id(changeset) do
    put_change(changeset, :id, "#{get_field(changeset, :type)}_#{get_field(changeset, :source_id)}")
  end
end

defmodule ArgosAggregation.ExternalLink do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    embeds_many :label, ArgosAggregation.TranslatedContent
    field :type, Ecto.Enum, values: [:image, :website]
    field :url, :string
  end

  def changeset(link, params \\ %{}) do
    link
    |> cast(params, [:type, :url])
    |> cast_embed(:label, [required: true])
    |> validate_required([:type, :url])
  end
end

defmodule ArgosAggregation.Person do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    field :name, :string
    field :uri, :string
  end

  def changeset(person, params \\ %{}) do
    person
    |> cast(params, [:name, :uri])
    |> validate_required([:name])
  end
end

defmodule ArgosAggregation.Organisation do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    field :name, :string
    field :uri, :string
  end

  def changeset(organisation, params \\ %{}) do
    organisation
    |> cast(params, [:name, :uri])
    |> validate_required([:name])
  end
end


defmodule ArgosAggregation.SpatialTopic do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    embeds_one :resource, ArgosAggregation.Gazetteer.Place
    embeds_many :topic_context_note, ArgosAggregation.TranslatedContent
  end

  def changeset(topic, params \\ %{}) do
    topic
    |> cast(params, [])
    |> cast_embed(:resource)
    |> cast_embed(:topic_context_note) # e.g. "Aufstellungsort" or "Fundort" in Arachne
    |> validate_required([:resource])
  end
end

defmodule ArgosAggregation.GeneralTopic do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    embeds_one :resource, ArgosAggregation.Thesauri.Concept
    embeds_many :topic_context_note, ArgosAggregation.TranslatedContent
  end

  def changeset(topic, params \\ %{}) do
    topic
    |> cast(params, [])
    |> cast_embed(:resource)
    |> cast_embed(:topic_context_note) # See spatial topic
    |> validate_required([:resource])
  end
end

defmodule ArgosAggregation.TemporalTopic do
  use ArgosAggregation.Schema

  import Ecto.Changeset

  embedded_schema do
    embeds_one :resource, ArgosAggregation.Chronontology.TemporalConcept
    embeds_many :topic_context_note, ArgosAggregation.TranslatedContent
  end

  def changeset(topic, params \\ %{}) do
    topic
    |> cast(params, [])
    |> cast_embed(:resource)
    |> cast_embed(:topic_context_note) # See spatial topic
    |> validate_required([:resource])
  end
end
