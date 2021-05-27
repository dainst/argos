

defmodule ArgosAggregation.Project do

  require Logger
  alias ArgosAggregation.{
    Thesauri, Gazetteer, Chronontology, TranslatedContent
  }

  defmodule Stakeholder do
    @enforce_keys [:label]
    defstruct [:label, :role, :uri, :type]
    @type t() :: %__MODULE__{
      label: [TranslatedContent.t()],
      role: String.t(),
      uri: String.t(),
      type: String.t(),
    }

    def from_map(%{} = data) do
      %Stakeholder{
        label:
          data["label"]
          |> Enum.map(&TranslatedContent.from_map/1),
        role: data["role"],
        uri: data["uri"],
        type: data["type"]
      }
    end
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

    def from_map(%{} = data) do
      %Person{
        firstname: data["firstname"],
        lastname: data["lastname"],
        title: data["title"],
        external_id: data["external_id"]
      }
    end
  end

  defmodule Image do
    @enforce_keys [:uri]
    defstruct [:uri, label: ""]
    @type t() :: %__MODULE__{
      label: [TranslatedContent.t()],
      uri: String.t()
    }

    def from_map(%{} = data) do
      %Image{
        label:
          data["label"]
          |> Enum.map(&TranslatedContent.from_map/1),
        uri: data["uri"]
      }
    end
  end

  defmodule ExternalLink do
    @enforce_keys [:uri]
    defstruct [:uri, label: "", role: "data"]
    @type t() :: %__MODULE__{
      label: [TranslatedContent.t()],
      uri: String.t(),
      role: String.t()
    }

    def from_map(%{} = data) do
      %ExternalLink{
        uri: data["uri"],
        role: data["role"],
        label:
          data["label"]
          |> Enum.map(&TranslatedContent.from_map/1)
      }
    end
  end

  defmodule Project do
    @enforce_keys [:id, :title]
    defstruct [:id, :title, description: [], doi: "", start_date: nil, end_date: nil, subject: [], spatial: [], temporal: [], images: [], stakeholders: [], external_links: [] ]
    @type t() :: %__MODULE__{
      id: String.t(),
      title: [TranslatedContent.t()],
      description: [TranslatedContent.t()],
      doi: String.t(),
      start_date: Date.t(),
      end_date: Date.t(),
      subject: [Thesauri.Concept.t()],
      spatial: [Gazetteer.Place.t()],
      temporal: [Chronontology.TemporalConcept.t()],
      stakeholders: [Stakeholder.t()],
      images: [Image.t()]
    }

    @doc """
    factory function for creating a proper %Project{} from a plain map e.g. from a db request
    """
    def from_map(%{} = data) do
      %Project{
        id: data["id"],
        title:
          data["title"]
          |> Enum.map(&TranslatedContent.from_map/1),
        description:
          data["description"]
          |> Enum.map(&TranslatedContent.from_map/1),
        doi: data["doi"],
        start_date: data["start_date"],
        end_date: data["end_date"],
        subject:
          data["subject"]
          |> Enum.map(&Thesauri.Concept.from_map/1),
        spatial:
          data["spatial"]
          |> Enum.map(&Gazetteer.Place.from_map/1),
        temporal:
          data["temporal"]
          |> Enum.map(&Chronontology.TemporalConcept.from_map/1),
        stakeholders:
          data["stakeholders"]
          |> Enum.map(&Stakeholder.from_map/1),
        images:
          data["images"]
          |> Enum.map(&Image.from_map/1)
      }
    end
  end

  defmodule DataProvider do
    @base_url Application.get_env(:argos_aggregation, :projects_url)
    alias ArgosAggregation.Project.ProjectParser

    def get_all() do
      "#{@base_url}/api/projects"
      |> get_project_list()
    end

    def get_by_date(%Date{} = date) do
      query =
        URI.encode_query(%{
          since: Date.to_string(date)
        })

      "#{@base_url}/api/projects?#{query}"
      |> get_project_list()
    end
    def get_by_date(%DateTime{} = date) do
      query =
        URI.encode_query(%{
          since: DateTime.to_naive(date)
        })

      "#{@base_url}/api/projects?#{query}"
      |> get_project_list()
    end

    defp get_project_list(url) do
      result =
        url
        |> HTTPoison.get()
        |> handle_result()

      case result do
        {:ok, data} ->
          data
          |> Enum.map(&ProjectParser.parse_project(&1))
        {:error, _ } ->
          []
      end
    end

    def get_by_id(id) do
      result =
        "#{@base_url}/api/projects/#{id}"
        |> HTTPoison.get()
        |> handle_result()

      case result do
        {:ok, data} ->
          ProjectParser.parse_project(data)
        {:error, reason } ->
          {:error, reason}
      end
    end

    defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}} = _response) do
      case Poison.decode(body) do
        {:ok, data} ->
          {:ok, data["data"]}
        {:error, reason} ->
          {:error, reason}
      end
    end
    defp handle_result({_, %HTTPoison.Response{status_code: 404}}) do
      {:error, 404}
    end
    defp handle_result({:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}) do
      Logger.error("No connection to #{@base_url}")
      {:error, :econnrefused}
    end
    defp handle_result({:error, %HTTPoison.Error{id: nil, reason: :timeout}}) do
      Logger.error("Timeout for #{@base_url}")
      {:error, :timeout}
    end
  end

  defmodule ProjectParser do
    def parse_project(data) do
      denormalized_lr =
        data["linked_resources"]
        |> denormalize_linked_resources()

      {data, denormalized_lr}
      |> convert_to_struct()
    end

    defp denormalize_linked_resources(lr) do
      lr
      |> get_linked_resources()
      |> convert_linked_resources()
    end

    defp get_linked_resources([] = res), do: res
    defp get_linked_resources([_|_] = resources) do
      resources
      |> Enum.map(&get_linked_resource(&1))
      |> Enum.reject(fn (val) ->
        val == :unknown
      end)
    end
    defp get_linked_resource(%{"linked_system" => "gazetteer", "res_id" => rid } = resource) do
      Gazetteer.DataProvider.get_by_id(rid)
      |> handle_response(resource)
    end
    defp get_linked_resource(%{"linked_system" => "chronontology", "res_id" => rid } = resource) do
      Chronontology.DataProvider.get_by_id(rid)
      |> handle_response(resource)
    end
    defp get_linked_resource(%{"linked_system" => "thesaurus", "res_id" => rid } = resource) do
      Thesauri.DataProvider.get_by_id(rid)
      |> handle_response(resource)
    end
    defp get_linked_resource(%{"linked_system" => unknown } ) do
      Logger.info("Unknown resource #{unknown}. Please provider matching data provider")
      :unknown
    end

    defp handle_response({:ok, res}, resource) do
      Map.put(resource, :linked_data, res)
    end
    defp handle_response({:error, err}, resource) do
      Logger.error(err)
      # TODO mark as retry candidate
      resource
    end

    defp convert_to_struct({proj, %{spatial: s, temporal: t, subject: c}}) do
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
            Date.from_iso8601!(val)
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
      %Stakeholder{label: [%{default: name}], role: role, uri: orc_id, type: :person}
    end

    defp create_name("" = _tp, p_ln, p_fn), do: "#{p_ln}, #{p_fn}"
    defp create_name(tp, p_ln, p_fn), do: "#{tp} #{p_ln}, #{p_fn}"

    defp convert_linked_resources(linked_resources) do
      linked_resources
      |> Enum.map(fn (%{:linked_data => _data, "descriptions" => desc} = res) ->
        labels = create_translated_content_list(desc)
        {labels, res}
      end)
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
      Map.put(acc, :temporal, acc.temporal ++ [ %{label: labels, resource: lr.linked_data}])
    end
    defp put_resource({labels, %{"linked_system" => "thesaurus"} = lr}, acc) do
      Map.put(acc, :subject, acc.subject ++ [ %{label: labels, resource: lr.linked_data}])
    end

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
    alias ArgosAggregation.ElasticSearchIndexer

    @interval Application.get_env(:argos_aggregation, :projects_harvest_interval)
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

    def reload(id) do
      DataProvider.get_by_id(id)
      |> ElasticSearchIndexer.index
    end
  end

end
