defmodule ArgosAggregation.Thesauri do
  require Logger

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


    def get_by_date(%Date{} = date) do
      date
      |> stream_pages
      |> Stream.map(&parse_single_doc(&1, :search))
    end

    defp stream_pages (date) do
      Stream.resource(
        fn ->
          case read_from_url("#{@base_url}/search.rdf?q=&change_note_date_from=#{Date.to_iso8601(date)}") do
            {:ok, xml} -> xpath(xml, ~x(//sdc:first/@rdf:resource))
            {:error, _xml} -> :halt
          end
        end,
        fn page_url ->
          case page_url do
            nil -> {:halt, page_url}
            page_url -> load_next_page(page_url)
          end
        end,
        fn _val ->
          Logger.info("Done reading thesaurus updates")
        end

      )

    end

    defp load_next_page(page_url) do
      IO.inspect(page_url)
      {:ok, xml} =
        page_url
        |> read_from_url

      with next_page <- xpath(xml, ~x(//sdc:next/@rdf:resource)o), #load optional, nil if not exists
          descr_list <- xpath(xml, ~x(//rdf:Description[descendant::sdc:link])l),
      do: {descr_list, next_page}

    end

    def get_all() do
      "#{@base_url}/hierarchy.rdf?depth=0"
      |> stream_read_hirarchy()
      |> Stream.flat_map(fn elements ->
        elements
        |> xpath(~x"//rdf:Description"l)
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
          roots
        end,
        #next_fun
        fn (root_data) ->
          case root_data do
            # last case roots are empty
            nil ->
              Logger.info("stopped becaus of nil")
              {:halt, root_data}
            [] ->
              Logger.info("stopped because of empty list")
              {:halt, root_data}
            # process roots until all are empty
            roots ->
              load_next_nodes(roots)
          end
        end,
        #end_fun
        fn (_root_data) ->
          Logger.debug("Finished tree traversing.")
        end
      )
    end

    defp get_hierarchy_url({:ok, id}) do
      "#{@base_url}/hierarchy/#{id}.rdf?dir=down"
    end

    defp load_next_nodes([ head | tail ]) do
      # load complet hirarchy of next
      Logger.info("Load next master branch #{head}")
      {:ok, xml} =
        head
        |> get_resource_id_from_uri
        |> get_hierarchy_url
        |> HTTPoison.get([], [timeout: 50_000, recv_timeout: 50_000]) # assemblage of the trees takes time, preventing timeout
        |> fetch_response

      {[xml], tail}
    end

    defp parse_single_doc(doc) do
      {:ok, id} =
        doc
        |> xpath(~x"//@rdf:about"s)
        |> get_resource_id_from_uri()

       doc |> assemble_concept(id)
    end

    defp parse_single_doc(doc, :search) do
      response =
        doc
        |> xpath(~x"//sdc:link/@rdf:resource")
        |> IO.inspect
        |> get_resource_id_from_uri()
      case response do
        {:ok, id} -> doc |> assemble_concept(id)
        error -> error
      end

    end



    def get_resource_id_from_uri("#{@base_url}/search.rdf" <> _), do: {:error, :search} #wrong url
    def get_resource_id_from_uri("#{@base_url}/" <> id ), do: {:ok, id}
    def get_resource_id_from_uri(charlist) when is_list(charlist), do: charlist |> to_string |> get_resource_id_from_uri
    def get_resource_id_from_uri(error), do: {:error, error}


    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_by_id(id) do
       with {:ok, xml} <-
          "#{@base_url}/#{id}.rdf"
          |> read_from_url
           do
            xml
            |> xpath(~x(rdf:Description[@rdf:about="#{@base_url}/#{id}"]))
            |> assemble_concept(id)
          else
            error -> error
        end
    end

    defp read_from_url(url) do
      url
      |> HTTPoison.get
      |> fetch_response
    end

    defp fetch_response({:ok, %{status_code: 200, body: body}}), do: {:ok, body}
    defp fetch_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end
    defp fetch_response({:error, error}), do: {:error, error.reason()}

    defp assemble_concept(xml, id) do
      concept =
        xml
        |> xml_to_labels(id)
        |> create_field_map(id)

      { :ok, concept }
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
      case read_path(xml, ~x(//skos:prefLabel)l) do
        [] -> xml_to_labels(xml, id, :skos_xllabel)
        val -> val
      end
    end

    defp xml_to_labels(xml, id, :skos_xllabel) do
      case read_path(xml, ~x(//skosxl:xllabel)l) do
        [] -> xml_to_labels(xml, id, :skos_literal)
        val -> val
      end
    end

    defp xml_to_labels(xml, id, :skos_literal) do
      case read_path(xml, ~x(//skosxl:literalForm)l) do
        [] -> Logger.warning("No labels found for concept #{@base_url}/#{id}.")
        val -> val
      end
    end

    defp read_path(xml, path) do
      xml
      |> xpath(path)
      |> Enum.map(&read_labels(&1))
    end

    defp read_labels(pref_label) do
      %{
        "lang" => xpath(pref_label, ~x(./@xml:lang)s),
        "text" => xpath(pref_label, ~x(./text(\))s)
      }
    end
  end



  defmodule Harvester do
    use GenServer
    alias ArgosAggregation.ElasticSearch.Indexer

    @interval Application.get_env(:argos_aggregation, :projects_harvest_interval)
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting thesaurus harvester with an interval of #{@interval}ms.")

      Process.send(self(), :run, [])
      {:ok, state}
    end

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{})
    end

    def handle_info(:run, state) do
      now =
        DateTime.now!(get_timezone())
        |> DateTime.to_date()

      run_harvest(state.last_run)

      state = %{state | last_run: now}
      schedule_next_harvest()
      {:noreply, state}
    end

    defp schedule_next_harvest() do
      Process.send_after(self(), :run, @interval)
    end

    def run_harvest() do
      DataProvider.get_all()
      |> Enum.each(&Indexer.index/1)
    end

    def run_harvest(%Date{} = date) do
      DataProvider.get_by_date(date)
      |> Enum.each(&Indexer.index/1)
    end
  end
end
