defmodule Argos.Data.Thesauri do

  defmodule Concept do
    alias DataModel.TranslatedContent

    @enforce_keys [:uri, :label]
    defstruct [:uri, :label]
    @type t() :: %__MODULE__{
      uri: String.t(),
      label: list(TranslatedContent.t()),
    }
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos, :thesauri_url)
    @behaviour Argos.Data.GenericProvider

    alias DataModel.TranslatedContent
    import SweetXml

    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    @impl Argos.Data.GenericProvider
    def get_all() do
      []
    end

    @impl Argos.Data.GenericProvider
    def get_by_id(id) do
      "#{@base_url}/#{id}.rdf"
      |> HTTPoison.get()
      |> parse_result(id)
    end

    @impl Argos.Data.GenericProvider
    def get_by_date(%NaiveDateTime{} = _date) do
      []
    end

    defp parse_result({:ok, %{status_code: 200, body: body}}, id) do
      xml =
        body
        |> SweetXml.parse()
        |> xml_to_concept(id)
      {:ok, xml}
    end

    defp parse_result({_, response}, _id) do
      {:error, response}
    end

    defp xml_to_concept(xml, id) do
      %Concept{
        label:
          xml
          |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skos:prefLabel)l)
          |> Enum.map(fn(pref_label) ->
            %TranslatedContent{
              lang: xpath(pref_label, ~x(./@xml:lang)s),
              text: xpath(pref_label, ~x(./text(\))s)
            }
          end),
        uri:
          "#{@base_url}/#{id}"
      }
    end
  end

  defmodule Harvester do
    # STUB
  end
end
