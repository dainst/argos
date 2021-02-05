defmodule Argos.Data.Thesauri do

  defmodule Concept do
    import DataModel.TranslatedContent

    @enforce_keys [:uri, :title]
    defstruct [:uri, :title]
    @type t() :: %__MODULE__{
      uri: String.t(),
      title: TranslatedContent.t(),
    }
  end

  defmodule DataProvider do
    import SweetXml

    @base_url Application.get_env(:argos, :thesauri_url)
    @behaviour Argos.Data.GenericProvider
    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_by_id(id) do
      "#{@base_url}/#{id}.rdf"
      |> HTTPoison.get()
      |> parse_result(id)
    end

    def search(_q) do
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
        title:
          xml
          |> xpath(~x(//rdf:Description[@rdf:about="#{@base_url}/#{id}"]/skos:prefLabel)l)
          |> Enum.map(fn(pref_label) ->
            %{
              "lang" => xpath(pref_label, ~x(./@xml:lang)s),
              "text" => xpath(pref_label, ~x(./text(\))s)
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
