defmodule ArgosCore.HTTPClient do

  def get(url, parse_response_as \\ :raw) do
    response =
      Finch.build(:get, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(parse_response_as)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} ->
        get(url, parse_response_as)
      {:error, %Mint.TransportError{reason: :timeout}} ->
        get(url, parse_response_as)
      response ->
        response
    end
  end

  def post(url, headers, payload, response_type \\ :raw) do
    response =
      Finch.build(:post, url, headers, payload)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

      case response do
        {:error, %Mint.TransportError{reason: :closed}} ->
          post(url, headers, payload, response_type)
        {:error, %Mint.TransportError{reason: :timeout}} ->
          post(url, headers, payload, response_type)
        response ->
          response
      end
  end

  def put(url, headers, payload, response_type \\ :raw) do
    response =
      Finch.build(:put, url, headers, payload)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} ->
        put(url, headers, payload, response_type)
      {:error, %Mint.TransportError{reason: :timeout}} ->
        put(url, headers, payload, response_type)
      response ->
        response
    end
  end
  def put(url, response_type \\ :raw) do
    response =
      Finch.build(:put, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} ->
        put(url, response_type)
      {:error, %Mint.TransportError{reason: :timeout}} ->
        put(url, response_type)
      response ->
        response
    end
  end

  def delete(url, response_type \\ :raw) do
    response =
      Finch.build(:delete, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} ->
        delete(url, response_type)
      {:error, %Mint.TransportError{reason: :timeout}} ->
        delete(url, response_type)
      response ->
        response
    end
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
  defp parse_response({:ok, %Finch.Response{status: 301, headers: headers, body: body}}, _) do
    {"location", location} =
      headers
      |> List.keyfind("location", 0)

    {:ok, %{status: 301, body: body, location: location}}
  end
  defp parse_response({:ok, %Finch.Response{status: status, body: body}}, _) do
    {:error, %{status: status, body: body}}
  end
  defp parse_response({:error, error}, _) do
    {:error, error}
  end
end
