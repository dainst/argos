defmodule ArgosCore.HTTPClient do

  def get(url, parse_response_as \\ :raw, retries \\ 5) do
    response =
      Finch.build(:get, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(parse_response_as)


    case response do
      {:error, %Mint.TransportError{reason: :closed}} when retries > 0 ->
        get(url, parse_response_as, retries - 1)
      {:error, %Mint.TransportError{reason: :timeout}} when retries > 0  ->
        get(url, parse_response_as, retries - 1)
      response ->
        response
    end
  end

  def post(url, headers, payload, response_type \\ :raw, retries \\ 5) do
    response =
      Finch.build(:post, url, headers, payload)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} when retries > 0 ->
        post(url, headers, payload, response_type, retries - 1)
      {:error, %Mint.TransportError{reason: :timeout}} when retries > 0 ->
        post(url, headers, payload, response_type, retries - 1)
      response ->
        response
    end
  end

  def put_payload(url, headers, payload, response_type \\ :raw, retries \\ 5) do
    response =
      Finch.build(:put, url, headers, payload)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} when retries > 0 ->
        put_payload(url, headers, payload, response_type, retries - 1)
      {:error, %Mint.TransportError{reason: :timeout}} when retries > 0 ->
        put_payload(url, headers, payload, response_type, retries - 1)
      response ->
        response
    end
  end
  def put(url, response_type \\ :raw, retries \\ 5) do
    response =
      Finch.build(:put, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} when retries > 0 ->
        put(url, response_type, retries - 1)
      {:error, %Mint.TransportError{reason: :timeout}} when retries > 0 ->
        put(url, response_type, retries - 1)
      response ->
        response
    end
  end

  def delete(url, response_type \\ :raw, retries \\ 5) do
    response =
      Finch.build(:delete, url)
      |> Finch.request(ArgosFinch)
      |> parse_response(response_type)

    case response do
      {:error, %Mint.TransportError{reason: :closed}} when retries > 0 ->
        delete(url, response_type, retries - 1)
      {:error, %Mint.TransportError{reason: :timeout}} when retries > 0 ->
        delete(url, response_type, retries - 1)
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
