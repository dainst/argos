defmodule Argos.Data.Chronontology do

  defmodule TemporalConcept do
    alias DataModel.TranslatedContent

    @enforce_keys [:uri, :label, :begin, :end]
    defstruct [:uri, :label, :begin, :end]
    @type t() :: %__MODULE__{
      uri: String.t(),
      label: TranslatedContent.t(),
      begin: integer(),
      end: integer()
    }
  end

  defmodule DataProvider do
    @behaviour Argos.Data.GenericProvider
    @base_url Application.get_env(:argos, :chronontology_url)

    alias DataModel.TranslatedContent

    require Logger

    @impl Argos.Data.GenericProvider
    def get_all() do
      []
    end

    @impl Argos.Data.GenericProvider
    def get_by_id(id) do
      HTTPoison.get("#{@base_url}/period/#{id}")
      |> parse_response()
      |> parse_period_data()
    end

    @impl Argos.Data.GenericProvider
    def get_by_date(%NaiveDateTime{} = _date) do
      []
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
      body
      |> Poison.decode()
    end

    defp parse_response({:ok, %HTTPoison.Response{status_code: code, request: req}}) do
      {:error, "Received unhandled status code #{code} for #{req.url}."}
    end

    defp parse_response({:error, error}) do
      {:error, error.reason()}
    end

    defp parse_period_data({:ok, data}) do
      # TODO: Es gibt potenziell mehrere timespan, wie damit umgehen?
      beginning =
        case data["resource"]["hasTimespan"] do
          [%{"begin" => %{"at" => at}}] ->
            at
          [%{"begin" => %{"notBefore" => notBefore}}] ->
            notBefore
          _ ->
            Logger.warning("Found no begin date for period #{data["resource"]["id"]}")
            ""
        end

      ending =
        case data["resource"]["hasTimespan"] do
          [%{"end" => %{"at" => at}}] ->
            at
          [%{"end" => %{"notAfter" => notAfter}}] ->
            notAfter
          _ ->
            Logger.warning("Found no end date for period #{data["resource"]["id"]}")
            ""
        end

      labels =
        data["resource"]["names"]
        |> Enum.map(fn({k, v_list}) ->
          v_list
          |> Enum.map(fn(v) ->
            %TranslatedContent{
              lang: k,
              text: v
            }
          end)
        end)

      {:ok, %TemporalConcept{
        uri: data["resource"]["uri"],
        label: labels,
        begin: beginning,
        end: ending
      }}
    end

    defp parse_period_data(error) do
      error
    end
  end
end
