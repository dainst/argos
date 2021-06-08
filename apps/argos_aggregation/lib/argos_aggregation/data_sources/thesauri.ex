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


    def get_all() do
      "#{@base_url}/hierarchy.rdf?depth=0"
      |> stream_read_hirarchy()
      |> Stream.flat_map(fn xml ->
        xpath(xml, ~x"//rdf:Description"l)
        |> Enum.map(&parse_single_doc(&1))
      end)
    end

    defp stream_read_hirarchy(url) do
      Logger.info("Start reading #{url}")
      Stream.resource(
        fn ->
          {:ok, xml} =
            HTTPoison.get( url )
            |> fetch_response

          roots =
            xml
            |> xpath(~x"//@rdf:about"l)
            |> MapSet.new
            |> MapSet.to_list
          %{roots: roots, data: xml}
        end,
        #next_fun
        fn (root_data) ->
          case root_data do
            # first case get a map with the first roots and the first xml data
            %{roots: roots, data: data} ->
              {[data], roots}

            # last case roots are empty
            nil ->
              Logger.info("stopped becaus of nil")
              {:halt, root_data}
            [] ->
              Logger.info("stopped becaus of empty list")
              {:halt, root_data}
            # process roots until all are empty
            roots ->
              load_next_root_elements(roots)
          end
        end,
        #end_fun
        fn (_root_data) ->
          Logger.debug("Finished tree traversing.")
        end
      )
    end

    defp load_next_root_elements([ head | tail ]) do
      # load all childs of next
      {:ok, xml} =
        "#{head}.rdf?depth=0"
        |> HTTPoison.get
        |> fetch_response

      # extract the new root ids
      new_roots =
        xml
        |> xpath(~x"//@rdf:about"l)

      broader =
        xml
        |> xpath(~x"//skos:broader/@rdf:resource"l)

      # add the root ids to the current ones
      # remove parente nodes preventing circles
      roots =
        ((new_roots ++ tail) -- broader) -- [head]
        |> MapSet.new
        |> MapSet.to_list

      {[xml], roots}
    end

    defp parse_single_doc(doc) do
      id =
        doc
        |> SweetXml.xpath(~x"//@rdf:about"s)
        |> get_resource_id_from_uri()

      {:ok, doc} |> assemble_concept(id)
    end

    def get_resource_id_from_uri("#{@base_url}/" <> id ), do: id
    def get_resource_id_from_uri(error), do: error


    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_by_id(id) do
        "#{@base_url}/#{id}.rdf"
        |> HTTPoison.get()
        |> fetch_response()
        |> assemble_concept(id)
    end

    def get_by_date(%Date{} = _date) do
      []
    end

    defp fetch_response({:ok, %{status_code: 200, body: body}}), do: {:ok, body}
    defp fetch_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end
    defp fetch_response({:error, error}), do: {:error, error.reason()}

    defp parse_xml({:ok, data}), do: SweetXml.parse(data)
    defp parse_xml(error), do: error

    defp assemble_concept({:ok, xml}, id) do
      labels =
          xml
          |> xml_to_labels(id)

      concept =
         create_field_map(labels, id)

      { :ok, concept }
    end

    defp assemble_concept(error, _) do
      error
    end

    defp create_field_map(labels, id) do
      %{
        "core_fields" => %{
          "source_id" => id,
          "type" => "concept",
          "uri" => "#{@base_url}/#{id}",
          "title" => labels
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
