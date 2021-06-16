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


  defmodule DataSourceClient do
    @doc """
    returns all changed concepts since the given date
    """
    @callback request_by_date(date :: %Date{}) :: {:ok, xml :: String.t} | {:error, String.t}

    @doc """
    Returns the rdf xml structur of all root nodes i.e. hierarchy.rdf depth=0
    """
    @callback request_root_level() :: {:ok, xml :: String.t} | {:error, String.t}

    @doc """
    Returns the complete downwards tree hierarchy of the given node id
    """
    @callback request_node_hierarchy(id :: String.t) :: {:ok, xml :: String.t} | {:error, String.t}

    @doc """
    Returns just the rdf document of the given id
    """
    @callback request_single_node(id :: String.t) :: {:ok, xml :: String.t} | {:error, String.t}

    @doc """
    Calls the given url and returns whatever comes in the response
    """
    @callback read_from_url(url :: String.t) :: {:ok, xml :: String.t} | {:error, String.t}

    @doc """
    same as read_from_url but with the possibility to add some options to the reuqest
    """
    @callback read_from_url(url :: String.t, options :: List.t) :: {:ok, xml :: String.t} | {:error, String.t}
  end

  defmodule DataSourceClient.Http do
    @behaviour DataSourceClient

    @base_url Application.get_env(:argos_aggregation, :thesauri_url)

    @impl DataSourceClient
    def request_by_date(%Date{} = date) do
       read_from_url("#{@base_url}/search.rdf?q=&change_note_date_from=#{Date.to_iso8601(date)}")
    end

    @impl DataSourceClient
    def request_root_level() do
      "#{@base_url}/hierarchy.rdf?depth=0"
      |> read_from_url()
    end

    @impl DataSourceClient
    def request_node_hierarchy(id) do
      "#{@base_url}/hierarchy/#{id}.rdf?dir=down"
      |> read_from_url([timeout: 50_000, recv_timeout: 50_000])
    end

    @impl DataSourceClient
    def request_single_node(id) do
      "#{@base_url}/#{id}.rdf"
      |> read_from_url()
    end

    @impl DataSourceClient
    def read_from_url(url) do
      url
      |> HTTPoison.get
      |> fetch_response
    end

    @impl DataSourceClient
    def read_from_url(url, options) when is_list(options) do
      url
      |> HTTPoison.get([], options)
      |> fetch_response
    end

    defp fetch_response({:ok, %{status_code: 200, body: body}}), do: {:ok, body}
    defp fetch_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end
    defp fetch_response({:error, error}), do: {:error, error.reason()}

  end


  defmodule DataProvider do
    import SweetXml
    require Logger

    @base_url Application.get_env(:argos_aggregation, :thesauri_url)

    def get_by_date(%Date{} = date, client \\ DataSourceClient.Http) do
      date
      |> stream_pages(client)
      |> Stream.map(fn element ->
        case element do
          {:error, _err} -> element
          _ -> parse_single_doc(element, :search)
        end
      end)
    end

    defp stream_pages(date, client) do
      Stream.resource(
        fn ->
          with {:ok, xml} <- client.request_by_date(date),
            {:ok, xml} <- check_validity(xml)
           do
            xpath(xml, ~x(//sdc:first/@rdf:resource))
           else
            error -> {[error], nil}
          end
        end,
        fn page_url ->
          case page_url do
            nil -> {:halt, page_url}
            page_url -> load_next_page(page_url, client)
          end
        end,
        fn _val ->
          Logger.info("Done reading thesaurus updates")
        end

      )

    end

    defp load_next_page(page_url, client) do

      with {:ok, xml} <- client.read_from_url(page_url),
          {:ok, xml} <- check_validity(xml),
          next_page <- xpath(xml, ~x(//sdc:next/@rdf:resource)o), #load optional, nil if not exists
          descr_list <- xpath(xml, ~x(//rdf:Description[descendant::sdc:link])l)
      do
        {descr_list, next_page}
      else
        error -> {[error], nil}
      end

    end

    def get_all(client \\ DataSourceClient.Http) do

      stream_read_hirarchy(client)
      |> Stream.flat_map(fn elements ->
        case elements do
          {:error, error} -> [elements]
          _ ->
            elements
            |> xpath(~x"//rdf:Description"l)
            |> Enum.map(&parse_single_doc(&1))
        end
      end)
    end

    defp stream_read_hirarchy(client) do

      Stream.resource(
        fn ->
          Logger.info("Start reading root level")
            with {:ok, xml} <- client.request_root_level(),
            {:ok, xml} <- check_validity(xml) do
              xml
              |> xpath(~x"//@rdf:about"l)
              |> MapSet.new
              |> MapSet.to_list
            else
              error -> error
            end
        end,
        #next_fun
        fn (root_data) ->
          case root_data do
            {:error, error} ->
              Logger.error(error)
              {[{:error, error}], nil}
            # last case roots are empty
            nil ->
              Logger.info("stopped becaus of nil")
              {:halt, root_data}
            [] ->
              Logger.info("stopped because of empty list")
              {:halt, root_data}
            # process roots until all are empty
            roots ->
              load_next_nodes(roots, client)
          end
        end,
        #end_fun
        fn (_root_data) ->
          Logger.debug("Finished tree traversing.")
        end
      )
    end

    defp load_next_nodes([ head | tail ], client) do
      # load complet hirarchy of next
      Logger.info("Load next master branch #{head}")
      with {:ok, id } <- get_resource_id_from_uri(head),
        {:ok, xml} <- client.request_node_hierarchy(id),
        {:ok, xml} <- check_validity(xml) do
          {[xml], tail}
      end

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
        |> get_resource_id_from_uri()
      case response do
        {:ok, id} -> doc |> assemble_concept(id)
        error -> error
      end

    end



    def get_resource_id_from_uri("#{@base_url}/search.rdf" <> _), do: {:error, :search} #wrong url
    def get_resource_id_from_uri("#{@base_url}/hierarchy/" <> id ), do: {:ok, id}
    def get_resource_id_from_uri("#{@base_url}/" <> id ), do: {:ok, id}
    def get_resource_id_from_uri(charlist) when is_list(charlist), do: charlist |> to_string |> get_resource_id_from_uri
    def get_resource_id_from_uri(error), do: {:error, error}


    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_by_id(id, client \\ DataSourceClient.Http) do
        with {:ok, xml} <- client.request_single_node(id),
          {:ok, xml} <- check_validity(xml)
          do
            xml
            |> xpath(~x(rdf:Description[@rdf:about="#{@base_url}/#{id}"]))
            |> assemble_concept(id)
          else
            error -> error
        end
    end

    defp check_validity(xml) do
      try do
       doc = xml |> parse()
       {:ok, doc}
      catch
        :exit, _ -> {:error, "Malformed xml document"}
      end
    end

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
