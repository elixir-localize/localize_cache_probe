defmodule LocalizeCacheProbe.Observation do
  @moduledoc """
  What the probe records about one response.

  `new/3` reads a status, the response headers and the body into an
  observation: the language the page was served in, how the response
  says it varies, whether it may be stored, and whether it came from a
  cache. Scenarios compare observations to reach a verdict.

  The language is the first tag of the `content-language` header, and
  the `lang` attribute of the `html` element where that header is
  absent. Both are kept, in lower case, because they can disagree.

  """

  alias LocalizeCacheProbe.Cache
  alias LocalizeCacheProbe.Headers

  # The `lang` attribute of the opening `html` tag, quoted or not.
  @html_lang ~r/<html\b[^>]*?\blang\s*=\s*["']?([A-Za-z0-9-]+)/i

  @enforce_keys [:status]
  defstruct status: nil,
            language: nil,
            content_language: nil,
            html_lang: nil,
            vary: [],
            vary_lines: 0,
            vary_by_line: [],
            cache_control: [],
            set_cookie?: false,
            cache_vendor: :unknown,
            cache_status: :unknown,
            age: nil,
            date: nil,
            body_hash: nil

  @typedoc """
  One response as the probe saw it.

  * `:status` is the HTTP status.

  * `:language` is `:content_language`, or `:html_lang` when that is `nil`.

  * `:vary` is the members of every `vary` line combined, and
    `:vary_lines` is how many lines carried them. `:vary_by_line` keeps
    the members of each line apart, in the order received.

  * `:cache_control` is the directives of every `cache-control` line.

  * `:set_cookie?` says whether the response set a cookie.

  * `:cache_vendor` and `:cache_status` come from `LocalizeCacheProbe.Cache`.

  * `:age` is the `age` header in seconds, and `:date` the `date` header
    as sent. A stored response keeps the `date` it was created with.

  * `:body_hash` is the SHA-256 of the body in lower case hexadecimal.

  """
  @type t :: %__MODULE__{
          status: non_neg_integer(),
          language: String.t() | nil,
          content_language: String.t() | nil,
          html_lang: String.t() | nil,
          vary: [String.t()],
          vary_lines: non_neg_integer(),
          vary_by_line: [[String.t()]],
          cache_control: [String.t()],
          set_cookie?: boolean(),
          cache_vendor: Cache.vendor(),
          cache_status: Cache.status(),
          age: non_neg_integer() | nil,
          date: String.t() | nil,
          body_hash: String.t()
        }

  @doc """
  Reads one response into an observation.

  ### Arguments

  * `status` is the HTTP status of the response.

  * `headers` is a list of `{name, value}` response headers, one entry
    for each header line.

  * `body` is the response body.

  ### Returns

  * A `t:t/0`.

  ### Examples

      iex> headers = [{"content-language", "fr"}, {"vary", "cookie"}, {"age", "12"}]
      iex> observation = LocalizeCacheProbe.Observation.new(200, headers, "")
      iex> {observation.language, observation.vary, observation.cache_status}
      {"fr", ["cookie"], :hit}

  """
  @spec new(non_neg_integer(), Headers.t(), binary()) :: t()
  def new(status, headers, body)
      when is_integer(status) and status >= 0 and is_list(headers) and is_binary(body) do
    content_language = content_language(headers)
    html_lang = html_lang(body)

    %__MODULE__{
      status: status,
      language: first_known(content_language, html_lang),
      content_language: content_language,
      html_lang: html_lang,
      vary: Headers.members(headers, "vary"),
      vary_lines: length(Headers.all(headers, "vary")),
      vary_by_line: Headers.members_by_line(headers, "vary"),
      cache_control: Headers.members(headers, "cache-control"),
      set_cookie?: match?([_ | _], Headers.all(headers, "set-cookie")),
      cache_vendor: Cache.vendor(headers),
      cache_status: Cache.status(headers),
      age: age(Headers.first(headers, "age")),
      date: Headers.first(headers, "date"),
      body_hash: hash(body)
    }
  end

  defp content_language(headers) do
    headers
    |> Headers.members("content-language")
    |> List.first()
  end

  defp html_lang(body) do
    case Regex.run(@html_lang, body, capture: :all_but_first) do
      [lang] -> String.downcase(lang)
      nil -> nil
    end
  end

  defp first_known(nil, html_lang) do
    html_lang
  end

  defp first_known(content_language, _html_lang) do
    content_language
  end

  defp age(nil) do
    nil
  end

  defp age(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {age, ""} when age >= 0 -> age
      _other -> nil
    end
  end

  defp hash(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end
end
