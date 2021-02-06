defmodule Argos.Data.Thesauri do

  defmodule Concept do
    alias Argos.Data.TranslatedContent

    @enforce_keys [:uri, :label]
    defstruct [:uri, :label]
    @type t() :: %__MODULE__{
      uri: String.t(),
      label: list(TranslatedContent.t()),
    }
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos, :thesauri_url)
    @behaviour Argos.Data.GenericDataProvider

    alias Argos.Data.TranslatedContent
    import SweetXml

    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    @impl Argos.Data.GenericDataProvider
    def get_all() do
      []
    end

    @impl Argos.Data.GenericDataProvider
    def get_by_id(id) do
      "#{@base_url}/#{id}.rdf"
      |> HTTPoison.get()
      |> parse_response()
      |> parse_concept_data(id)
    end

    @impl Argos.Data.GenericDataProvider
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

      {:ok, %Concept{
        label: labels,
        uri: "#{@base_url}/#{id}"
      }}
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
    end
  end

  defmodule Harvester do
    # STUB
  end
end
