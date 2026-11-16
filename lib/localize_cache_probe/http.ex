defmodule LocalizeCacheProbe.HTTP do
  @moduledoc """
  Makes one `GET` request and returns the response as it was sent.

  The primary API is `get/2`. Each call opens a connection, sends one
  request over HTTP/1.1 and closes the connection. Redirects are not
  followed, because a redirect is itself something the probe reports,
  and certificates are verified against the operating system's store.

  Response headers come back one entry for each header line, in the
  order received. That is why the probe uses Mint: `:httpc` keeps only
  one line of a repeated `vary` header, and two `vary` lines are one of
  the cases the probe tests.

  """

  alias LocalizeCacheProbe.Headers

  @connect_timeout 10_000
  @receive_timeout 15_000
  @user_agent "localize-cache-probe/0.1"

  @typedoc "A response: its status, its header lines and its body."
  @type response :: %{status: non_neg_integer(), headers: Headers.t(), body: binary()}

  @doc """
  Makes a `GET` request to a URL.

  ### Arguments

  * `url` is an `http` or `https` URL.

  * `headers` is a list of `{name, value}` request headers to send as
    well as `user-agent` and `accept`. The default is `[]`.

  ### Returns

  * `{:ok, response}` where `response` has a `:status`, the `:headers`
    one entry for each line, and the `:body`, or

  * `{:error, exception}` when the URL is not an `http` or `https` URL,
    the connection fails, or the response does not arrive in time.

  ### Examples

      iex> {:error, exception} = LocalizeCacheProbe.HTTP.get("ftp://example.com/")
      iex> Exception.message(exception)
      ~s(expected an http or https URL, got: "ftp://example.com/")

  """
  @spec get(String.t(), Headers.t()) :: {:ok, response()} | {:error, Exception.t()}
  def get(url, headers \\ []) when is_binary(url) and is_list(headers) do
    with {:ok, target} <- target(url),
         {:ok, conn} <- connect(target) do
      request(conn, target, headers)
    end
  end

  defp target(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, port: port} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and is_integer(port) ->
        {:ok, %{scheme: scheme(scheme), host: host, port: port, path: path(uri)}}

      _other ->
        {:error, ArgumentError.exception("expected an http or https URL, got: #{inspect(url)}")}
    end
  end

  defp scheme("http") do
    :http
  end

  defp scheme("https") do
    :https
  end

  defp path(%URI{path: path, query: query}) do
    path = path || "/"

    if is_nil(query) do
      path
    else
      path <> "?" <> query
    end
  end

  defp connect(target) do
    Mint.HTTP.connect(target.scheme, target.host, target.port,
      mode: :passive,
      protocols: [:http1],
      transport_opts: [timeout: @connect_timeout]
    )
  end

  defp request(conn, target, headers) do
    headers = [
      {"user-agent", @user_agent},
      {"accept", "text/html,*/*;q=0.8"},
      {"connection", "close"} | headers
    ]

    case Mint.HTTP.request(conn, "GET", target.path, headers, nil) do
      {:ok, conn, _ref} -> receive_response(conn, %{status: 0, headers: [], body: []})
      {:error, conn, reason} -> failed(conn, reason)
    end
  end

  defp receive_response(conn, response) do
    case Mint.HTTP.recv(conn, 0, @receive_timeout) do
      {:ok, conn, entries} -> continue(conn, Enum.reduce(entries, response, &collect/2))
      {:error, conn, reason, _entries} -> failed(conn, reason)
    end
  end

  defp continue(conn, %{error: reason}) do
    failed(conn, reason)
  end

  defp continue(conn, %{done?: true} = response) do
    _closed = Mint.HTTP.close(conn)
    body = IO.iodata_to_binary(Enum.reverse(response.body))

    {:ok, %{status: response.status, headers: response.headers, body: body}}
  end

  defp continue(conn, response) do
    receive_response(conn, response)
  end

  defp collect({:status, _ref, status}, response) do
    %{response | status: status}
  end

  defp collect({:headers, _ref, headers}, response) do
    %{response | headers: response.headers ++ headers}
  end

  defp collect({:data, _ref, data}, response) do
    %{response | body: [data | response.body]}
  end

  defp collect({:done, _ref}, response) do
    Map.put(response, :done?, true)
  end

  defp collect({:error, _ref, reason}, response) do
    Map.put(response, :error, reason)
  end

  defp failed(conn, reason) do
    _closed = Mint.HTTP.close(conn)

    {:error, reason}
  end
end
