defmodule ArgosAggregation.Thesauri do
  defmodule Concept do
    use ArgosAggregation.Schema

    alias ArgosAggregation.CoreFields

    import Ecto.Changeset

    embedded_schema do
      embeds_one(:core_fields, CoreFields)
    end

    def changeset(concept, params \\ %{}) do
      concept
      |> cast(params, [])
      |> cast_embed(:core_fields)
      |> validate_required([:core_fields])
    end

    def create(params) do
      Concept.changeset(%Concept{}, params)
      |> apply_action(:create)
    end
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :thesauri_url)

    import SweetXml
    require Logger

    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_all() do
      []
    end

    def get_by_id(id) do
      response =
        "#{@base_url}/#{id}.rdf"
        |> HTTPoison.get()
        |> parse_response()

      case response do
        {:ok, data} ->
          parse_concept_data(data, id)
        error ->
          error
      end
    end

    def get_by_date(%Date{} = _date) do
      []
    end

    defp parse_response({:ok, %{status_code: 200, body: body}}) do
      {:ok, body}
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end

    defp parse_response({:error, error}) do
      {:error, error.reason()}
    end

    defp parse_concept_data(data, id) do
      labels =
        data
        |> SweetXml.parse()
        |> xml_to_labels(id)

      {
        :ok,
        %{
          "core_fields" => %{
            "source_id" => id,
            "type" => "concept",
            "uri" => "#{@base_url}/#{id}",
            "title" => labels
          }
        }
      }
    end

    defp xml_to_labels(xml, id) do
      xml
      |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skos:prefLabel)l)
      |> Enum.map(fn pref_label ->
        %{
          "lang" => xpath(pref_label, ~x(./@xml:lang)s),
          "text" => xpath(pref_label, ~x(./text(\))s)
        }
      end)
      |> case do
        [] ->
          xml
          |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skosxl:literalForm)l)
          |> Enum.map(fn pref_label ->
            %{
              "lang" => xpath(pref_label, ~x(./@xml:lang)s),
              "text" => xpath(pref_label, ~x(./text(\))s)
            }
          end)

        val ->
          val
      end
      |> case do
        [] ->
          Logger.warning("No labels found for concept #{@base_url}/#{id}.")
          []

        val ->
          val
      end
    end
  end

  defmodule Harvester do
    # STUB
  end
end
