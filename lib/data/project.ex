

defmodule Argos.Data.Project do

  require Logger
  alias Argos.Data.{
    Thesauri, Gazetteer, Chronontology, TranslatedContent
  }

  defmodule Stakeholder do
    @enforce_keys [:label]
    defstruct [:label, :role, :uri, :type]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      role: String.t(),
      uri: String.t(),
      type: String.t(),
    }
  end

  defmodule Person do
    @enforce_keys [:firstname, :lastname]
    defstruct [:firstname, :lastname, title: "", external_id: ""]
    @type t() :: %__MODULE__{
      firstname: String.t(),
      lastname: String.t(),
      title: String.t(),
      external_id: String.t()
    }
  end

  defmodule Image do
    @enforce_keys [:uri]
    defstruct [:uri, label: ""]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      uri: String.t()
    }
  end

  defmodule ExternalLink do
    @enforce_keys [:uri]
    defstruct [:uri, label: "", role: "data"]
    @type t() :: %__MODULE__{
      label: TranslatedContent.t(),
      uri: String.t(),
      role: String.t()
    }
  end

  defmodule Project do
    @enforce_keys [:id, :title]
    defstruct [:id, :title, description: %{}, doi: "", start_date: nil, end_date: nil, subject: [], spatial: [], temporal: [], images: [], stakeholders: [], external_links: [] ]
    @type t() :: %__MODULE__{
      id: String.t(),
      title: TranslatedContent.t(),
      description: TranslatedContent.t(),
      doi: String.t(),
      start_date: Date.t(),
      end_date: Date.t(),
      subject: [Argos.Data.Thesauri.Concept.t()],
      spatial: [Place.t()],
      temporal: [TemporalConcept.t()],
      stakeholders: [Stakeholder.t()],
      images: [Image.t()]
    }
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos, :projects_url)
    @behaviour Argos.Data.AbstractDataProvider

    alias Argos.Data.Project.ProjectParser

    @impl Argos.Data.AbstractDataProvider
    def get_all() do
      query_projects("#{@base_url}/api/projects")
    end

    @impl Argos.Data.AbstractDataProvider
    def get_by_date(%Date{} = date) do
      query = URI.encode_query(%{ since: Date.to_string(date) })
      url = "#{@base_url}/api/projects?#{query}"
      query_projects(url)
    end
    def get_by_date(%DateTime{} = date) do
      query = URI.encode_query(%{ since: DateTime.to_naive(date) })
      url = "#{@base_url}/api/projects?#{query}"
      query_projects(url)
    end
    def get_by_date(date) when is_binary(date) do
      parse_date(date)
      |> get_by_date
    end

    defp query_projects(url) do
      Logger.info("Running projects harvest at #{url}.")
      %{"data" => data} =
        url
        |> HTTPoison.get
        |> handle_result
      # TODO: Switch to project code after Erga got updated
      ProjectParser.parse_project(data)
    end


    defp parse_date(date_string) do
      {:ok, date} = Date.from_iso8601(date_string)
      date
    end

    @impl Argos.Data.AbstractDataProvider
    def get_by_id(id) do
      url = "#{@base_url}/api/projects/#{id}"
      query_projects(url)
    end

    defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}} = _response), do: Poison.decode!(body)
    defp handle_result({:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}) do
      Logger.warn("No connection")
      exit("no connection to Erga server.")
    end
    defp handle_result(call), do: Logger.error("Cannot process result: #{call}")
  end

  defmodule ProjectParser do
    def parse_project(data) do
      Enum.map(data, &denormalize/1)
      |> Enum.map(&convert_to_struct/1)
    end

    defp denormalize(%{"linked_resources" => lr} = proj) do
      rich_res = get_linked_resources(lr)
      Map.put(proj, "linked_resources", rich_res)
    end

    defp get_linked_resources([] = res), do: res
    defp get_linked_resources([_|_] = resources), do: Enum.map(resources, &get_linked_resources/1)
    defp get_linked_resources(%{"linked_system" => "gazetteer", "res_id" => rid } = resource) do
      Gazetteer.DataProvider.get_by_id(rid) |> handle_response(resource)
    end
    defp get_linked_resources(%{"linked_system" => "chronontology", "res_id" => rid } = resource) do
      Chronontology.DataProvider.get_by_id(rid) |> handle_response(resource)
    end
    defp get_linked_resources(%{"linked_system" => "thesaurus", "res_id" => rid } = resource) do
      Thesauri.DataProvider.get_by_id(rid) |> handle_response(resource)
    end
    defp get_linked_resources(%{"linked_system" => unknown } = resource ) do
      Logger.info("Unknown resource #{unknown}. Please provider matching data provider")
      resource
    end

    defp handle_response({:ok, res}, resource), do: Map.put(resource, :linked_data, res)
    defp handle_response({:error, err}, resource) do
      Logger.error(err)
      # TODO mark as retry candidate
      resource
    end

    defp convert_to_struct(proj) do
      %{spatial: s, temporal: t, subject: c} = convert_linked_resources(proj)
      project = %Project{
        id: proj["id"],
        title:  create_translated_content_list(proj["titles"]),
        description: create_translated_content_list(proj["descriptions"]),
        start_date:
        case proj["starts_at"] do
          nil ->
            nil
          val ->
            Date.from_iso8601!(val)
        end,
        end_date:
        case proj["ends_at"] do
          nil ->
            nil
          val ->
            Date.from_iso8601(val)
        end,
        doi: get_doi(proj),
        spatial: s,
        temporal: t,
        subject: c,
        stakeholders: create_stakeholder_list(proj),
        images: create_images(proj),
        external_links: create_external_links(proj)
      }

      project
    end

    defp get_doi(%{"doi" => doi}), do: doi
    defp get_doi(_), do: ""

    defp create_external_links(%{"external_links" => ex_list}) do
      for %{"url" => u, "labels" => l} <- ex_list, do: %ExternalLink{uri: u, label: create_translated_content_list(l)}
    end

    defp create_images(%{"images" => i_list}) do
      for %{"path" => p, "labels" => l} <- i_list, do: %Image{uri: p, label: create_translated_content_list(l)}
    end

    defp create_stakeholder_list(%{"stakeholders" => st_list}) do
      for st <- st_list, do: create_stakeholder(st)
    end

    defp create_stakeholder(%{ "person" => %{"first_name" => p_fn, "last_name" => p_ln, "title" => tp, "orc_id" => orc_id }, "role" => role}) do
      name = create_name(tp, p_ln, p_fn)
      %Stakeholder{label: %{default: name}, role: role, uri: orc_id, type: :person}
    end

    defp create_name("" = _tp, p_ln, p_fn), do: "#{p_ln}, #{p_fn}"
    defp create_name(tp, p_ln, p_fn), do: "#{tp} #{p_ln}, #{p_fn}"

    defp convert_linked_resources(%{"linked_resources" => linked_resources}) do
      for %{:linked_data => _data, "description" => desc} = res <- linked_resources do
        labels = create_translated_content_list(desc)
        {labels, res}
      end
      |> Enum.reduce(%{
        spatial: [],
        temporal: [],
        subject: []
      }, &put_resource/2)
    end

    defp put_resource({labels, %{"linked_system" => "gazetteer"} = lr}, acc) do
      Map.put(acc, :spatial, acc.spatial ++ [ %{label: labels, resource: lr.linked_data}])
    end
    defp put_resource({labels, %{"linked_system" => "chronontology"} = lr}, acc) do
      Map.put(acc, :spatial, acc.temporal ++ [ %{label: labels, resource: lr.linked_data}])
    end
    defp put_resource({labels, %{"linked_system" => "thesaurus"} = lr}, acc) do
      Map.put(acc, :spatial, acc.subject ++ [ %{label: labels, resource: lr.linked_data}])
    end
    defp put_resource(_, acc), do: acc

    @spec create_translated_content_list(List.t()) :: [TranslatedContent.t()]
    def create_translated_content_list([%{"language_code" => _, "content" => _}|_] = tlc_list)  do
      # takes a list with translated content items coming from the project-api and reduce them to a search-api conform list of maps
      for tlc <- tlc_list, do: %{lang: tlc["language_code"], text: tlc["content"]}
    end
    def create_translated_content_list([] = tlc_list), do: tlc_list
    def create_translated_content_list(nil), do: []

  end

  defmodule Harvester do
    use GenServer
    alias Argos.ElasticSearchIndexer

    @interval Application.get_env(:argos, :projects_harvest_interval)
    # TODO Noch nicht refactored!
    defp get_timezone() do
      "Etc/UTC"
    end

    def init(state) do
      state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

      Logger.info("Starting projects harvester with an interval of #{@interval}ms.")

      Process.send(self(), :run, [])
      {:ok, state}
    end

    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{})
    end

    def handle_info(:run, state) do # TODO: Übernommen, warum info und nicht cast/call?
      now = DateTime.now!(get_timezone())
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
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end

    def run_harvest(%DateTime{} = datetime) do
      DataProvider.get_by_date(datetime)
      |> Enum.each(&ElasticSearchIndexer.index/1)
    end

  end


  # TODO: Handle error results
end
