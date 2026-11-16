defmodule LocalizeCacheProbe.Cache do
  @moduledoc """
  Recognises the cache in front of an application from the headers of a
  response, and records what each vendor documents about the `vary`
  header.

  The primary API is `vendor/1`, which names the cache, `status/1`, which
  says whether a response came from it, and `vary_note/1`, which returns
  the vendor's documented treatment of `vary` with the page it came from.

  Recognition is a heuristic over headers a vendor is known to add. A
  cache that adds none, such as `plug_http_cache`, is `:unknown`, and
  `status/1` then relies on the standard `age` header.

  """

  @typedoc "Response headers as name and value pairs."
  @type headers :: LocalizeCacheProbe.Headers.t()

  @typedoc "The cache recognised in front of the application."
  @type vendor ::
          :akamai
          | :cloudflare
          | :cloudfront
          | :fastly
          | :front_door
          | :google
          | :nginx
          | :varnish
          | :unknown

  @typedoc "Whether a response was served from a cache."
  @type status :: :hit | :miss | :uncacheable | :unknown

  @typedoc "What a vendor documents about `vary`, and where."
  @type note :: %{summary: String.t(), source: String.t()}

  # Checked in this order: Fastly is built on Varnish and sends its `via`
  # header too, so it must be tried first.
  @vendors [:cloudflare, :cloudfront, :fastly, :akamai, :front_door, :google, :varnish, :nginx]

  # Substrings of a cache status header, lower case, and what each means.
  # Checked in this order, so "RefreshHit" and "TCP_REMOTE_HIT" are hits.
  @status_tokens [
    {"hit", :hit},
    {"revalidated", :hit},
    {"stale", :hit},
    {"updating", :hit},
    {"miss", :miss},
    {"expired", :miss},
    {"dynamic", :uncacheable},
    {"bypass", :uncacheable},
    {"nostore", :uncacheable},
    {"nocache", :uncacheable}
  ]

  # Each note was taken from the vendor's own page in November 2026, and
  # says what that page says and no more. None has been tested here.
  @notes %{
    akamai: %{
      summary:
        "Stores no response that has a vary header, unless it is accept-encoding on " <>
          "compressed content. That keeps out vary: accept-language as well as vary: cookie.",
      source: "https://techdocs.akamai.com/property-mgr/docs/rm-vary-header"
    },
    cloudflare: %{
      summary:
        "Ignores vary until a Cache Rule turns it on. The rule can normalise " <>
          "accept-language before the lookup, and its default folds a region into its language.",
      source: "https://blog.cloudflare.com/vary-support/"
    },
    cloudfront: %{
      summary:
        "Keys on the headers its cache policy names, and none by default, so it keeps one " <>
          "copy of a page. It removes vary values other than accept-encoding, cookie and " <>
          "the headers it forwards.",
      source:
        "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/" <>
          "RequestAndResponseBehaviorCustomOrigin.html"
    },
    front_door: %{
      summary:
        "Does not document vary. With caching on it does not forward accept-language " <>
          "to the origin, and it removes set-cookie from a response it can cache.",
      source: "https://learn.microsoft.com/en-us/azure/frontdoor/front-door-caching"
    },
    google: %{
      summary:
        "Stores no response whose vary names a header outside a fixed list, which has " <>
          "neither cookie nor accept-language, unless that header is in the cache key " <>
          "settings. It stores no response that has set-cookie.",
      source: "https://docs.cloud.google.com/cdn/docs/caching"
    }
  }

  @doc """
  Names the cache in front of an application from its response headers.

  ### Arguments

  * `headers` is a list of `{name, value}` response headers. Names are
    matched without regard to case.

  ### Returns

  * A `t:vendor/0`, which is `:unknown` when no header identifies a cache.

  ### Examples

      iex> LocalizeCacheProbe.Cache.vendor([{"cf-cache-status", "HIT"}])
      :cloudflare

      iex> LocalizeCacheProbe.Cache.vendor([{"content-type", "text/html"}])
      :unknown

  """
  @spec vendor(headers()) :: vendor()
  def vendor(headers) when is_list(headers) do
    Enum.find(@vendors, :unknown, &vendor?(&1, headers))
  end

  @doc """
  Says whether a response was served from a cache.

  A vendor's own status header is read first: `cf-cache-status`, `x-cache`,
  `x-cache-status`, then `x-varnish`. The standard `age` header is the
  fallback, and a response that carries one is a hit: an origin sends no
  `age`, so its presence says a cache answered, even at `age: 0` for a
  response stored in the same second. Varnish sends `age: 0` on a miss
  as well, which is why its own header is read first.

  ### Arguments

  * `headers` is a list of `{name, value}` response headers.

  ### Returns

  * `:hit` when the response came from a cache, or

  * `:miss` when the cache fetched it from the origin, or

  * `:uncacheable` when the cache says it will not store the response, or

  * `:unknown` when no header says.

  ### Examples

      iex> LocalizeCacheProbe.Cache.status([{"x-cache", "Miss from cloudfront"}])
      :miss

      iex> LocalizeCacheProbe.Cache.status([{"age", "42"}])
      :hit

  """
  @spec status(headers()) :: status()
  def status(headers) when is_list(headers) do
    signals = [
      token_status(header(headers, "cf-cache-status")),
      token_status(last_token(header(headers, "x-cache"))),
      token_status(header(headers, "x-cache-status")),
      varnish_status(header(headers, "x-varnish")),
      age_status(header(headers, "age"))
    ]

    Enum.find(signals, :unknown, &(&1 != :unknown))
  end

  @doc """
  Returns what a vendor documents about the `vary` header.

  ### Arguments

  * `vendor` is a `t:vendor/0`.

  ### Returns

  * `{:ok, note}` where `note` has a `:summary` and the `:source` page it
    was read from, or

  * `:error` when no documentation has been read for that vendor.

  ### Examples

      iex> {:ok, note} = LocalizeCacheProbe.Cache.vary_note(:akamai)
      iex> note.source
      "https://techdocs.akamai.com/property-mgr/docs/rm-vary-header"

      iex> LocalizeCacheProbe.Cache.vary_note(:unknown)
      :error

  """
  @spec vary_note(vendor()) :: {:ok, note()} | :error
  def vary_note(vendor) when is_atom(vendor) do
    Map.fetch(@notes, vendor)
  end

  defp vendor?(:cloudflare, headers) do
    present?(headers, "cf-cache-status") or present?(headers, "cf-ray") or
      contains?(headers, "server", "cloudflare")
  end

  defp vendor?(:cloudfront, headers) do
    present?(headers, "x-amz-cf-pop") or present?(headers, "x-amz-cf-id") or
      contains?(headers, "via", "cloudfront")
  end

  defp vendor?(:fastly, headers) do
    present?(headers, "x-fastly-request-id") or contains?(headers, "x-served-by", "cache-")
  end

  defp vendor?(:akamai, headers) do
    contains?(headers, "server", "akamai") or contains?(headers, "x-cache", "akamai")
  end

  defp vendor?(:front_door, headers) do
    present?(headers, "x-azure-ref")
  end

  defp vendor?(:google, headers) do
    contains?(headers, "via", "1.1 google")
  end

  defp vendor?(:varnish, headers) do
    present?(headers, "x-varnish") or contains?(headers, "via", "varnish")
  end

  defp vendor?(:nginx, headers) do
    contains?(headers, "server", "nginx")
  end

  defp token_status(nil) do
    :unknown
  end

  defp token_status(value) when is_binary(value) do
    value = String.downcase(value)

    case Enum.find(@status_tokens, fn {token, _status} -> String.contains?(value, token) end) do
      {_token, status} -> status
      nil -> :unknown
    end
  end

  # A response that passed through several nodes lists one status for
  # each, and the last is the node nearest the visitor.
  defp last_token(nil) do
    nil
  end

  defp last_token(value) when is_binary(value) do
    value
    |> String.split(",")
    |> List.last()
    |> String.trim()
  end

  # Varnish sends the id of this request, and on a hit the id of the
  # request that stored the object as well.
  defp varnish_status(nil) do
    :unknown
  end

  defp varnish_status(value) when is_binary(value) do
    case String.split(value) do
      [_request, _stored | _rest] -> :hit
      [_request] -> :miss
      [] -> :unknown
    end
  end

  defp age_status(nil) do
    :unknown
  end

  defp age_status(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {age, ""} when age >= 0 -> :hit
      _other -> :unknown
    end
  end

  defp header(headers, name) do
    LocalizeCacheProbe.Headers.first(headers, name)
  end

  defp present?(headers, name) do
    not is_nil(header(headers, name))
  end

  defp contains?(headers, name, fragment) do
    value = header(headers, name)

    if is_nil(value) do
      false
    else
      String.contains?(String.downcase(value), fragment)
    end
  end
end
