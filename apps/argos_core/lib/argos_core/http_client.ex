defmodule ArgosCore.HTTPClient do

  def get(url, parse_response_as \\ :raw) do
    Finch.build(:get, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(parse_response_as)
  end

  def post(url, headers, payload, response_type \\ :raw) do
    Finch.build(:post, url, headers, payload)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  def put(url, headers, payload, response_type \\ :raw) do
    Finch.build(:put, url, headers, payload)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end
  def put(url, response_type \\ :raw) do
    Finch.build(:put, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  def delete(url, response_type \\ :raw) do
    Finch.build(:delete, url)
    |> Finch.request(ArgosCoreFinchProcess)
    |> parse_response(response_type)
  end

  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :raw)
       when status >= 200 and status < 300 do
    {:ok, body}
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :xml)
       when status >= 200 and status < 300 do
    {:ok, SweetXml.parse(body)}
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, :json)
       when status >= 200 and status < 300 do
    {:ok, Poison.decode!(body)}
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, _) do
    {:error, %{status: status, body: body}}
  end
  defp parse_response({:error, error}, _) do
    {:error, error}
  end
end
