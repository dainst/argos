defmodule ArgosCore.HTTPClient do

  @doc """

  """
  def get(url, response_type \\ :text) do
    Finch.build(:get, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  @doc """

  """
  def post(url, headers, payload, response_type \\ :text) do
    Finch.build(:post, url, headers, payload)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  @doc """

  """
  def put(url, headers, payload, response_type \\ :text) do
    Finch.build(:put, url, headers, payload)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  @doc """

  """
  def put(url, response_type \\ :text) do
    Finch.build(:put, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  @doc """

  """
  def delete(url, response_type \\ :text) do
    Finch.build(:delete, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :text) when status >= 200 and status < 300 do
    { :ok, body }
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :xml) when status >= 200 and status < 300 do
    { :ok, SweetXml.parse(body) }
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :json) when status >= 200 and status < 300 do
    { :ok, Poison.decode!(body) }
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, _) do
    { :error, %{status: status, body: body}}
  end
  defp parse_response({:error, error}, _) do
    { :error, error }
  end
end
