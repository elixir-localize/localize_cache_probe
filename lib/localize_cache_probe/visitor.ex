defmodule LocalizeCacheProbe.Visitor do
  @moduledoc """
  One visitor to the application: a name, the `accept-language` their
  browser sends, and the cookies the application has given them.

  The primary API is `new/2`, which creates a visitor, and `visit/2`,
  which requests a URL as that visitor and returns the visitor with any
  new cookies and an observation of the response.

  A visitor's stored locale is never forged. The probe sets it the way a
  person would, by visiting the URL that chooses a locale, and the
  application's own signed session cookie then carries it.

  The cookie jar is deliberately simple. The probe talks to one host, so
  the `domain` and `path` of a cookie are not consulted, and a cookie is
  removed only when it is sent with an empty value or `max-age=0`.

  """

  alias LocalizeCacheProbe.Headers
  alias LocalizeCacheProbe.HTTP
  alias LocalizeCacheProbe.Observation

  @enforce_keys [:name]
  defstruct name: nil, accept_language: nil, cookies: %{}

  @typedoc """
  A visitor.

  * `:name` labels the visitor in a report.

  * `:accept_language` is the header value their browser sends, or `nil`
    to send none.

  * `:cookies` is the cookies they hold, by name.

  """
  @type t :: %__MODULE__{
          name: String.t(),
          accept_language: String.t() | nil,
          cookies: %{String.t() => String.t()}
        }

  @doc """
  Creates a visitor with no cookies.

  ### Arguments

  * `name` labels the visitor in a report.

  * `options` is a keyword list of options.

  ### Options

  * `:accept_language` is the `accept-language` header the visitor
    sends. The default is `nil`, which sends none.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> visitor = LocalizeCacheProbe.Visitor.new("A", accept_language: "fr")
      iex> {visitor.name, visitor.accept_language, visitor.cookies}
      {"A", "fr", %{}}

  """
  @spec new(String.t(), Keyword.t()) :: t()
  def new(name, options \\ []) when is_binary(name) and is_list(options) do
    %__MODULE__{name: name, accept_language: accept_language(options[:accept_language])}
  end

  @doc """
  Returns the request headers a visitor sends.

  ### Arguments

  * `visitor` is a `t:t/0`.

  ### Returns

  * A list of `{name, value}` headers: `accept-language` when the
    visitor has one, and `cookie` when they hold any cookies, with the
    cookies in order of name.

  ### Examples

      iex> visitor = LocalizeCacheProbe.Visitor.new("A", accept_language: "fr")
      iex> LocalizeCacheProbe.Visitor.request_headers(visitor)
      [{"accept-language", "fr"}]

  """
  @spec request_headers(t()) :: Headers.t()
  def request_headers(%__MODULE__{accept_language: accept_language, cookies: cookies}) do
    language_header(accept_language) ++ cookie_header(cookies)
  end

  @doc """
  Updates a visitor's cookies from the `set-cookie` lines of a response.

  ### Arguments

  * `visitor` is a `t:t/0`.

  * `headers` is a list of `{name, value}` response headers.

  ### Returns

  * The visitor with each cookie stored, replaced or removed. A line
    that does not hold a `name=value` pair is ignored.

  ### Examples

      iex> visitor = LocalizeCacheProbe.Visitor.new("A")
      iex> visitor = LocalizeCacheProbe.Visitor.remember(visitor, [{"set-cookie", "k=v; Path=/"}])
      iex> visitor.cookies
      %{"k" => "v"}

  """
  @spec remember(t(), Headers.t()) :: t()
  def remember(%__MODULE__{cookies: cookies} = visitor, headers) when is_list(headers) do
    cookies =
      headers
      |> Headers.all("set-cookie")
      |> Enum.reduce(cookies, &store/2)

    %{visitor | cookies: cookies}
  end

  @doc """
  Requests a URL as a visitor.

  ### Arguments

  * `visitor` is a `t:t/0`.

  * `url` is an `http` or `https` URL.

  ### Returns

  * `{:ok, visitor, observation}` where `visitor` holds any cookies the
    response set and `observation` is a `t:LocalizeCacheProbe.Observation.t/0`, or

  * `{:error, exception}` when the request could not be made.

  ### Examples

      iex> visitor = LocalizeCacheProbe.Visitor.new("A")
      iex> {:error, %ArgumentError{}} = LocalizeCacheProbe.Visitor.visit(visitor, "not a url")

  """
  @spec visit(t(), String.t()) :: {:ok, t(), Observation.t()} | {:error, Exception.t()}
  def visit(%__MODULE__{} = visitor, url) when is_binary(url) do
    with {:ok, response} <- HTTP.get(url, request_headers(visitor)) do
      observation = Observation.new(response.status, response.headers, response.body)

      {:ok, remember(visitor, response.headers), observation}
    end
  end

  defp accept_language(value) when is_binary(value) and value != "" do
    value
  end

  defp accept_language(_other) do
    nil
  end

  defp language_header(nil) do
    []
  end

  defp language_header(accept_language) do
    [{"accept-language", accept_language}]
  end

  defp cookie_header(cookies) when map_size(cookies) == 0 do
    []
  end

  defp cookie_header(cookies) do
    value =
      cookies
      |> Enum.sort()
      |> Enum.map_join("; ", fn {name, value} -> name <> "=" <> value end)

    [{"cookie", value}]
  end

  defp store(line, cookies) do
    [pair | attributes] = String.split(line, ";")

    case String.split(pair, "=", parts: 2) do
      [name, value] -> put(cookies, String.trim(name), String.trim(value), attributes)
      [_no_value] -> cookies
    end
  end

  defp put(cookies, "", _value, _attributes) do
    cookies
  end

  defp put(cookies, name, "", _attributes) do
    Map.delete(cookies, name)
  end

  defp put(cookies, name, value, attributes) do
    if Enum.any?(attributes, &expired?/1) do
      Map.delete(cookies, name)
    else
      Map.put(cookies, name, value)
    end
  end

  defp expired?(attribute) do
    normalised =
      attribute
      |> String.replace(" ", "")
      |> String.downcase()

    normalised == "max-age=0"
  end
end
