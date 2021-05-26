defmodule ArgosAggregation.Thesauri do

  defmodule Concept do
    alias ArgosAggregation.TranslatedContent

    @enforce_keys [:id, :uri, :label]
    defstruct [:id, :uri, :label]
    @type t() :: %__MODULE__{
      id: String.t(),
      uri: String.t(),
      label: [TranslatedContent.t()],
    }

    def from_map(%{} = data) do
      %Concept{
        id: data["id"],
        uri: data["uri"],
        label:
          data["label"]
          |> Enum.map(&TranslatedContent.from_map/1)
      }
    end

  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :thesauri_url)
    @behaviour ArgosAggregation.AbstractDataProvider

    alias ArgosAggregation.TranslatedContent
    import SweetXml
    require Logger

    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    @impl ArgosAggregation.AbstractDataProvider
    def get_all() do
      []
    end

    @impl ArgosAggregation.AbstractDataProvider
    def get_by_id(id) do
      "#{@base_url}/#{id}.rdf"
      |> HTTPoison.get()
      |> parse_response()
      |> parse_concept_data(id)
    end

    @impl ArgosAggregation.AbstractDataProvider
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

    defp parse_concept_data({:ok, data}, id) do
      labels =
        data
        |> SweetXml.parse()
        |> xml_to_labels(id)

      {
        :ok, %Concept{
          id: id,
          uri: "#{@base_url}/#{id}",
          label: labels
        }
      }
    end

    defp parse_concept_data({:error, _} = error, _id) do
      error
    end

    defp xml_to_labels(xml, id) do
      xml
      |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skos:prefLabel)l)
      |> Enum.map(fn(pref_label) ->
        %TranslatedContent{
          lang: xpath(pref_label, ~x(./@xml:lang)s),
          text: xpath(pref_label, ~x(./text(\))s)
        }
      end)
      |> case do
        [] ->
          xml
          |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skosxl:literalForm)l)
          |> Enum.map(fn(pref_label) ->
            %TranslatedContent{
              lang: xpath(pref_label, ~x(./@xml:lang)s),
              text: xpath(pref_label, ~x(./text(\))s)
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
