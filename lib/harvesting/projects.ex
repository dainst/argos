

defmodule Argos.Harvesting.Projects do
  use GenServer

  require Logger
  alias Argos.Harvesting.Chronontology.ChronontologyClient
  alias Argos.Data.{
    Thesauri, Gazetteer
  }
  alias DataModel.{Projects, ExternalLink, Image, Stakeholder, TemporalConcept, TranslatedContent}

  @base_url Application.get_env(:argos, :projects_url)
  @interval Application.get_env(:argos, :projects_harvest_interval)

  @elastic_search Application.get_env(:argos, :elasticsearch_url)

  defp get_timezone() do
    "Etc/UTC"
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    state = Map.put(state, :last_run, DateTime.now!(get_timezone()))

    Logger.info("Starting projects harvester with an interval of #{@interval}ms.")

    Process.send(self(), :run, [])
    {:ok, state}
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
    "#{@base_url}/api/projects"
    |> start
  end

  def run_harvest(%DateTime{} = datetime) do
    query = URI.encode_query(%{ since: DateTime.to_naive(datetime) })

    "#{@base_url}/api/projects?#{query}"
    |> start
  end

  defp start(url) do
    Logger.info("Running projects harvest at #{url}.")
    query_result =
      url
      |> HTTPoison.get
      |> handle_result
    # TODO: Switch to project code after Erga got updated
   query_result["data"]
    |> Enum.map(&denormalize/1)
    |> Enum.map(&convert_to_struct/1)
    |> Enum.each(&upsert/1)

  end

  defp convert_to_struct(proj) do
    doi = if Map.has_key?(proj, "doi"), do: proj["doi"], else: ""
    %{spatial: s, temporal: t, subject: c} = convert_linked_resources(proj["linked_resources"])
    stakeholders = convert_stakeholders(proj["stakeholders"])
    images = convert_images(proj["images"])
    ex_link = convert_external_links(proj["external_links"])
    project = %Projects{
      id: proj["project_key"],
      title:  get_translated_content(proj["titles"]),
      description: get_translated_content(proj["descriptions"]),
      start_date: Date.from_iso8601!(proj["starts_at"]),
      end_date: Date.from_iso8601!(proj["ends_at"]),
      doi: doi,
      spatial: s,
      temporal: t,
      subject: c,
      stakeholders: stakeholders,
      images: images,
      external_links: ex_link
    }

    project
  end

  defp convert_external_links(ex_list) do
    for ex <- ex_list, do: %ExternalLink{uri: ex["url"], label: get_translated_content(ex["labels"])}
  end

  defp convert_images(i_list) do
    for i <- i_list, do: %Image{uri: i["path"], label: get_translated_content(i["labels"])}
  end

  defp convert_stakeholders(st_list) do
    Enum.map(st_list, fn stake ->
        case stake do
          %{ "person" => %{"first_name" => p_fn, "last_name" => p_ln, "title" => tp, "orc_id" => orc_id }, "role" => role} ->
              name = if tp != "" do
                "#{tp} #{p_ln}, #{p_fn}"
              else
                "#{p_ln}, #{p_fn}"
              end

              %Stakeholder{label: %{default: name}, role: role, uri: orc_id, type: :person}
        end
      end)
    end


  defp convert_linked_resources(linked_resources) do
    linked_resources
    |> Enum.map(fn resource ->
        labels =
          resource["descriptions"]
          |> Enum.map(fn(%{"language_code" => lang, "content" => content}) ->
            %TranslatedContent{
              lang: lang,
              text: content
            }
          end)
        {labels, resource}
      end)
    |> Enum.reduce(%{
      spatial: [],
      temporal: [],
      subject: []
    }, fn({labels, lr}, acc) ->
      case lr["linked_system"] do
        "gazetteer" ->
          Map.put(acc, :spatial, acc.spatial ++ [%{
            label: labels,
            resource: lr.linked_data
          }])
        "chronontology" ->
          %{:linked_data => [%{"resource" => main} | _]} = lr
          [%{"begin" => %{"notBefore" => begin}, "end" => %{"notAfter" => ending}}] = main["hasTimespan"]
          time = %TemporalConcept{uri: lr["uri"], label: get_translated_content(lr["labels"]), begin: begin, end: ending }
          Map.put(acc, :temporal, acc.temporal ++ [%{
            label: labels,
            resource: time
          }])
        "thesaurus" ->
          Map.put(acc, :subject, acc.subject ++ [%{
            label: labels,
            resource: lr.linked_data
          }])
        _ ->
          acc
      end
    end)
  end

  @spec get_translated_content(List.t()) :: TranslatedContent.t()
  defp get_translated_content(ts_content)  do
    # takes a list with translated content items coming from the project-api and reduce them to a search-api conform map
    Enum.reduce(ts_content, %{}, &(Map.put(&2, String.to_atom(&1["language_code"]), &1["content"])) )
  end

  defp denormalize(proj) do
    rich_res = get_linked_resources(proj["linked_resources"])
    Map.put(proj, "linked_resources", rich_res)
  end

  defp get_linked_resources(resources) when is_list(resources) do
    if length(resources) > 0 do
      Enum.map(resources, &get_linked_resources/1)
    else
      resources
    end
  end

  defp get_linked_resources(%{"linked_system" => _ } = resource) do
     response = case resource["linked_system"] do
        "gazetteer" ->
          {:ok, place } = Gazetteer.DataProvider.get_by_id(resource["res_id"])
          place
        "chronontology" -> ChronontologyClient.fetch_by_id!(%{id: resource["res_id"]})
        "thesaurus" ->
          {:ok, concept} = Thesauri.DataProvider.get_by_id(resource["res_id"])
          concept
        _ -> nil
     end
     Map.put(resource, :linked_data, response)
  end

  defp upsert(project) do
    Logger.info("Upserting '#{project.id}'.")
    body =
      %{
        doc: project,
        doc_as_upsert: true
      }
      |> Poison.encode!

    "#{@elastic_search}/_update/project-#{project.id}"
    |> HTTPoison.post!(body, [{"Content-Type", "application/json"}])
  end

  defp handle_result({:ok, %HTTPoison.Response{status_code: 200, body: body}} = _response) do
    Poison.decode!(body)
  end

  defp handle_result({:error, %HTTPoison.Error{id: nil, reason: :econnrefused}}) do
    Logger.warn("No connection")
    exit('no db connection')
  end

  defp handle_result(call) do
    Logger.error("Cannot process result: #{call}")
    exit('no db connection')
  end

  # TODO: Handle error results
end
