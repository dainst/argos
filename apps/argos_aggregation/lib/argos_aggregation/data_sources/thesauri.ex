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


  defmodule DataSourceClient.Http do
    @base_url Application.get_env(:argos_aggregation, :thesauri_url)

    def request_by_date(%Date{} = date) do
       read_from_url("#{@base_url}/search.rdf?q=&change_note_date_from=#{Date.to_iso8601(date)}")
    end

    def request_root_level() do
      "#{@base_url}/hierarchy.rdf?depth=0"
      |> read_from_url()
    end

    def request_node_hierarchy(id) do
      "#{@base_url}/hierarchy/#{id}.rdf?dir=down"
      |> read_from_url([timeout: 50_000, recv_timeout: 50_000])
    end

    def request_single_node(id) do
      "#{@base_url}/#{id}.rdf"
      |> read_from_url()
    end

    def read_from_url(url) do
      url
      |> HTTPoison.get
      |> fetch_response
    end

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

  defmodule DataSourceClient.Local do

    alias ArgosAggregation.ElasticSearch

    def request_single_node(id) do
      ElasticSearch.DataProvider.get_doc("concept_#{id}")
    end

  end


  defmodule DataProvider do
    require Logger

    alias ArgosAggregation.ElasticSearch.Indexer
    alias ArgosAggregation.Thesauri.ConceptParser

    def get_by_date(%Date{} = date) do
      date
      |> stream_pages
      |> Stream.map(fn element ->
        case element do
          {:error, _err} -> element
          _ -> ConceptParser.Search.parse_single_doc(element)
        end
      end)
    end

    defp stream_pages(date) do
      Stream.resource(
        fn ->
          case DataSourceClient.Http.request_by_date(date) do
            {:ok, xml} -> ConceptParser.Search.load_first_page_url(xml)
            error -> {[error], nil}
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
      case DataSourceClient.Http.read_from_url(page_url) do
        {:ok, xml} -> ConceptParser.Search.load_next_page_items(xml)
        error -> {[error], nil}
      end
    end

    def get_all() do
      with {:ok, xml} <- DataSourceClient.Http.request_root_level() do
        stream_read_hierarchy(xml)
        |> Stream.flat_map(fn elements ->
          case elements do
            {:error, _} -> [elements]
            _ -> ConceptParser.Hierarchy.read_list_of_descriptions(elements)
          end
        end)
      end
    end

    defp stream_read_hierarchy(xml) do
      Stream.resource(
        fn ->
          Logger.info("Start reading root level")
          ConceptParser.Hierarchy.read_root_level(xml)
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
              load_next_nodes(roots)
          end
        end,
        #end_fun
        fn (_root_data) ->
          Logger.debug("Finished tree traversing.")
        end
      )
    end

    defp load_next_nodes([ head | tail ]) do
      # load complete hierarchy of next
      Logger.info("Load next master branch #{head}")
      with {:ok, id } <- ConceptParser.Utils.get_resource_id_from_uri(head),
        {:ok, xml} <- DataSourceClient.Http.request_node_hierarchy(id),
        {:ok, xml} <- ConceptParser.Utils.check_validity(xml) do
          {[xml], tail}
      else
        error ->
          Logger.error(error)
          {[error], nil}
      end
    end



    @doc """
    Retrieves the XML for a given thesauri id.
    Returns
    - {:ok, xml_struct} on success, where xml_struct is the RDF XML parsed by SweetXML
    - {:error, response} for all HTTP responses besides status 200.
    """
    def get_by_id(id, force_reload \\ true) do
      case force_reload do
        true ->
          get_by_id_from_source(id)
        false ->
          get_by_id_locally(id)
      end
    end

    defp get_by_id_from_source(id) do
      case DataSourceClient.Http.request_single_node(id) do
        {:ok, xml} -> ConceptParser.read_single_document(xml, id)
        error -> error
      end
    end

    defp get_by_id_locally(id) do
      case DataSourceClient.Local.request_single_node(id) do
        {:ok, _} = concept -> concept
        {:error, 404} ->
          case get_by_id_from_source(id) do
            {:ok, concept} = res ->
              ArgosAggregation.ElasticSearch.Indexer.index(concept)
              res
            error->
              error
          end
      end
    end


  end


  defmodule ConceptParser do
    @base_url Application.get_env(:argos_aggregation, :thesauri_url)

    import SweetXml

    defmodule Factory do
      @base_url Application.get_env(:argos_aggregation, :thesauri_url)
      @field_type Application.get_env(:argos_aggregation, :thesauri_type_key)
      require Logger

      def assemble_concept(xml, id) do
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
            "type" => @field_type,
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

    defmodule Utils do
      @base_url Application.get_env(:argos_aggregation, :thesauri_url)

      def check_validity(xml) do
        try do
         doc = xml |> parse()
         {:ok, doc}
        catch
          :exit, _ -> {:error, "Malformed xml document"}
        end
      end

      def get_resource_id_from_uri("#{@base_url}/search.rdf" <> _), do: {:error, :search} #wrong url
      def get_resource_id_from_uri("#{@base_url}/hierarchy/" <> id ), do: {:ok, id}
      def get_resource_id_from_uri("#{@base_url}/" <> id ), do: {:ok, id}
      def get_resource_id_from_uri(charlist) when is_list(charlist), do: charlist |> to_string |> get_resource_id_from_uri
      def get_resource_id_from_uri(error), do: {:error, error}
    end

    defmodule Search do

      @doc """
      read first page url

      returns url | error
      """
      def load_first_page_url(xml) do
        case Utils.check_validity(xml) do
          {:ok, xml} -> xpath(xml, ~x(//sdc:first/@rdf:resource))
          error -> error
        end
      end

      @doc """
      reads all the description items of this page and the url of the next page

      returns {[data], url} | {[error], nil}
      """
      def load_next_page_items(xml) do
        case Utils.check_validity(xml) do
         {:ok, xml } ->
          next_page = xpath(xml, ~x(//sdc:next/@rdf:resource)o)
          descr_list = xpath(xml, ~x(//rdf:Description[descendant::sdc:link])l)
          {descr_list, next_page}
         error -> {[error], nil}
        end
      end

      @doc """
      parses a single
      <rdf:Description>
        <sdc:link rdf:resource="thesaurus/_id">
        </sdc:link>
      </rdf:Description>
      doc from a search result page

      returns {:ok, %Concept{}}
      """
      def parse_single_doc(doc) do
        response =
          doc
          |> xpath(~x"//sdc:link/@rdf:resource")
          |> Utils.get_resource_id_from_uri
        case response do
          {:ok, id} -> doc |> Factory.assemble_concept(id)
          error -> error
        end
      end

    end

    defmodule Hierarchy do
      @doc """
      reads from a root level hierarchy the root level urls and returns them in a unique list

      returns [unique urls] | error
      """
      def read_root_level(xml) do
        case Utils.check_validity(xml) do
          {:ok, xml} ->
            xml
            |> xpath(~x"//@rdf:about"l)
            |> MapSet.new
            |> MapSet.to_list
          error -> error
        end
      end

      @doc """
      creates a List of [ <rdf:Descriptions> ... ] from a hierarchy
      """
      def read_list_of_descriptions(xml) do
        xml
        |> xpath(~x"//rdf:Description"l)
        |> Enum.map(&parse_single_doc(&1))
      end

      @doc """
      parses a single <rdf:Description rdf:about="thesaurus/_id"></rdf:Description> doc from a hierarchy

      returns {:ok, %Concept{}}
      """
      defp parse_single_doc(doc) do
        {:ok, id} =
          doc
          |> xpath(~x"//@rdf:about"s)
          |> Utils.get_resource_id_from_uri()

         doc |> Factory.assemble_concept(id)
      end
    end

    @doc """
    read_single_document will extract the concept information
    identified by the given id from the given xml

    it expects the information to be in a proper rdf document
    <rdf:Description rdf:about="thesaurus/_12355"> ...
    </rdf:Description>
    """
    def read_single_document(xml, id) do
      case Utils.check_validity(xml) do
        {:ok, xml} -> xml
          |> xpath(~x(rdf:Description[@rdf:about="#{@base_url}/#{id}"]))
          |> Factory.assemble_concept(id)
        error -> error
      end
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
      |> Enum.each(&index_concept/1)
    end

    def run_harvest(%Date{} = date) do
      DataProvider.get_by_date(date)
      |> Enum.each(&index_concept/1)
    end

    defp index_concept({:ok, concept}) do
      Indexer.index(concept)
    end
    defp index_concept({:error, err}) do
      Logger.error(err)
    end
    defp index_concept(error) do
      Logger.error(error)
    end

  end
end
