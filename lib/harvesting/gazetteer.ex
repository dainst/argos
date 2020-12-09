defmodule Argos.Harvesting.Gazetteer do
  use GenServer

  require Logger

  defmodule GazetteerClient do
    def fetch!(query \\ "*", offset \\ 0, limit \\ 1) do
      params = %{q: query, limit: limit, offset: offset}

      HTTPoison.get!(base_url(), [], [{:params, params}])
      |> response_unwrap
    end

    def fetch_total!(query) do
      case fetch!(query, 0, 0) do
        %{"total" => total} -> total
        _ -> raise "Unexpected response without a total."
      end
    end

    defp base_url do
      Application.get_env(:argos, :gazetteer_url) <> "/search.json"
    end

    defp response_unwrap(%HTTPoison.Response{status_code: 200, body: body}) do
      Poison.decode!(body)
    end

    defp response_unwrap(%HTTPoison.Response{status_code: code, request: %{url: url}}) do
      raise "Gazetteer fetch returned unexpected '#{code}' on GET '#{url}'"
    end
  end

  defmodule ElasticsearchClient do
    @headers [{"Content-Type", "application/json"}]

    def save!(document, id) do
      HTTPoison.post!(update_url(id), upsert_content(document), @headers)
      |> unwrap_response!
    end

    defp unwrap_response!(%HTTPoison.Response{body: body}) do
      result = Poison.decode!(body)

      if Map.has_key?(result, "error") do
        raise result["error"]
      end

      result
    end

    defp update_url(id) do
      Application.get_env(:argos, :elasticsearch_url) <> "/_update/#{id}"
    end

    defp upsert_content(document) do
      %{
        doc: document,
        doc_as_upsert: true
      }
      |> Poison.encode!()
    end
  end

  defmodule GazetteerHarvester do
    @batch_size 100

    def harvest!(%Date{} = lastModified) do
      query = build_query_string(lastModified)
      total = GazetteerClient.fetch_total!(query)
      offsets = Enum.filter(0..total, fn i -> rem(i, @batch_size) == 0 end)

      Enum.map(offsets, &harvest_batch!(query, &1, @batch_size))
      total
    end

    defp build_query_string(%Date{} = date) do
      date_s = Date.to_iso8601(date)
      "(lastChangeDate:>=#{date_s})"
    end

    defp harvest_batch!(query, offset, batch_size) do
      GazetteerClient.fetch!(query, offset, batch_size)
      |> save_resources!
    end

    defp save_resources!(%{"result" => results}) do
      Enum.map(results, &save_resource!(&1))
    end

    defp save_resources!(_) do
      raise "Unexpected response without field 'result'"
    end

    defp save_resource!( %{"gazId" => id} = result) do
      id = "gazetteer-#{id}"
      ElasticsearchClient.save!(result, id)
    end

    defp save_resource!(_) do
      raise "Unable to save malformed resource."
    end
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    state = Map.put(state, :last_run, Date.utc_today())
    Process.send(self(), :run, [])
    {:ok, state}
  end

  def handle_info(:run, state) do
    # Schedules a harvesting of gazetteer datasets and sets the state.last_run
    # field to the date just before the harvesting started.
    today = Date.utc_today()
    result = run_harvest(state.last_run)

    # A new harvest is scheduled regardless of the status of the last one
    schedule_next_harvest()

    # On error, do not update the state.last_run field, so that documents not
    # picked up in one run, might be picket up later.
    case result do
      {:ok, _} -> {:noreply, %{state | last_run: today}}
      {:error, _} -> {:noreply, state}
    end
  end

  def run_harvest(%Date{} = date) do
    # Gets all chronontology documents changed since the provided date and puts them
    # in our index.
    Logger.debug("Starting harvest for documents changed since: #{date}")

    try do
      total = GazetteerHarvester.harvest!(date)
      Logger.debug("Successfully indexd #{total} documents changed since: #{date}")
      {:ok, nil}
    rescue
      e in RuntimeError ->
        Logger.error(e.message)
        {:error, e.message}
    end
  end

  defp schedule_next_harvest() do
    Process.send_after(self(), :run, interval())
  end

  defp interval do
    Application.get_env(:argos, :gazetteer_harvest_interval)
  end
end
