defmodule LocalizeCacheProbe.Target do
  @moduledoc """
  The application page the probe is pointed at, and how a visitor
  chooses a locale there.

  The primary API is `new/2`, which validates what a developer supplied,
  `choose_url/2`, which returns the URL a visitor requests to store a
  locale, and `localized_url/2`, which returns the page's URL with a
  locale in it.

  The page is one whose URL holds no locale, since that is where the
  session and `accept-language` decide. By default a visitor chooses a
  locale by requesting the page with a `locale` query parameter, which
  is what `Localize.Plug.PutLocale` reads and `Localize.Plug.PutSession`
  then stores. An application that chooses another way gives a
  `:choose_url` template.

  """

  @default_param "locale"
  @placeholder "{locale}"

  # A locale and a parameter name go into a URL, so only characters that
  # need no escaping there are accepted.
  @locale ~r/\A[A-Za-z0-9]+(-[A-Za-z0-9]+)*\z/
  @param ~r/\A[A-Za-z0-9_-]+\z/

  @enforce_keys [:url, :locales]
  defstruct url: nil,
            locales: [],
            param: @default_param,
            choose_url: nil,
            regions: nil,
            localized_url: nil

  @typedoc """
  A target.

  * `:url` is the page to request.

  * `:locales` is two or more locales the application supports. The
    first is the one a browser asks for and the second the one stored.

  * `:param` is the query parameter that chooses a locale.

  * `:choose_url` is a URL template holding `{locale}`, or `nil` to add
    `:param` to `:url`.

  * `:regions` is two regional locales of one language that the
    application serves differently, or `nil`.

  * `:localized_url` is a template for the page's URL with a locale in
    it, holding `{locale}`, or `nil`.

  """
  @type t :: %__MODULE__{
          url: String.t(),
          locales: [String.t(), ...],
          param: String.t(),
          choose_url: String.t() | nil,
          regions: [String.t(), ...] | nil,
          localized_url: String.t() | nil
        }

  @doc """
  Validates a URL and options into a target.

  ### Arguments

  * `url` is the `http` or `https` URL of a page whose URL holds no
    locale.

  * `options` is a keyword list of options.

  ### Options

  * `:locales` is a list of two or more different locales the
    application supports, such as `["fr", "de"]`. Required.

  * `:param` is the query parameter that chooses a locale. The default
    is `"locale"`.

  * `:choose_url` is a URL template holding `{locale}`, for an
    application that chooses a locale some other way. The default is
    `nil`.

  * `:regions` is a list of two regional locales of one language that
    the application serves differently, such as `["fr-FR", "fr-CH"]`.
    The default is `nil`, and the scenario that needs them is skipped.

  * `:localized_url` is a URL template holding `{locale}` for the same
    page with the locale in its URL, such as
    `"https://example.com/{locale}/pricing"`. The default is `nil`, and
    the scenario that needs it is skipped.

  ### Returns

  * `{:ok, target}`, or

  * `{:error, exception}` naming the first value that is not valid.

  ### Examples

      iex> {:ok, target} = LocalizeCacheProbe.Target.new("https://example.com/pricing", locales: ["fr", "de"])
      iex> target.param
      "locale"

      iex> {:error, exception} = LocalizeCacheProbe.Target.new("https://example.com/", locales: ["fr"])
      iex> Exception.message(exception)
      ~s(expected :locales to be two or more different locales, got: ["fr"])

  """
  @spec new(String.t(), Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(url, options \\ []) when is_list(options) do
    target = %__MODULE__{
      url: url,
      locales: options[:locales],
      param: Keyword.get(options, :param, @default_param),
      choose_url: options[:choose_url],
      regions: options[:regions],
      localized_url: options[:localized_url]
    }

    with :ok <- validate_url(target.url, :url),
         :ok <- validate_locales(target.locales),
         :ok <- validate_param(target.param),
         :ok <- validate_template(target.choose_url, :choose_url),
         :ok <- validate_regions(target.regions),
         :ok <- validate_template(target.localized_url, :localized_url) do
      {:ok, target}
    end
  end

  @doc """
  Returns the URL a visitor requests to choose a locale.

  ### Arguments

  * `target` is a `t:t/0`.

  * `locale` is one of the target's locales.

  ### Returns

  * The `:choose_url` template with `{locale}` filled in, or the
    target's `:url` with the locale added as a query parameter.

  ### Examples

      iex> {:ok, target} = LocalizeCacheProbe.Target.new("https://example.com/pricing?tab=2", locales: ["fr", "de"])
      iex> LocalizeCacheProbe.Target.choose_url(target, "de")
      "https://example.com/pricing?tab=2&locale=de"

  """
  @spec choose_url(t(), String.t()) :: String.t()
  def choose_url(%__MODULE__{choose_url: nil, url: url, param: param}, locale)
      when is_binary(locale) do
    url
    |> URI.parse()
    |> URI.append_query(param <> "=" <> locale)
    |> URI.to_string()
  end

  def choose_url(%__MODULE__{choose_url: template}, locale) when is_binary(locale) do
    String.replace(template, @placeholder, locale)
  end

  @doc """
  Returns the page's URL with a locale in it.

  ### Arguments

  * `target` is a `t:t/0`.

  * `locale` is one of the target's locales.

  ### Returns

  * `{:ok, url}` with `{locale}` filled in, or

  * `:error` when the target has no `:localized_url`.

  ### Examples

      iex> options = [locales: ["fr", "de"], localized_url: "https://example.com/{locale}/pricing"]
      iex> {:ok, target} = LocalizeCacheProbe.Target.new("https://example.com/pricing", options)
      iex> LocalizeCacheProbe.Target.localized_url(target, "de")
      {:ok, "https://example.com/de/pricing"}

  """
  @spec localized_url(t(), String.t()) :: {:ok, String.t()} | :error
  def localized_url(%__MODULE__{localized_url: nil}, locale) when is_binary(locale) do
    :error
  end

  def localized_url(%__MODULE__{localized_url: template}, locale) when is_binary(locale) do
    {:ok, String.replace(template, @placeholder, locale)}
  end

  defp validate_url(url, option) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _other ->
        invalid(option, "an http or https URL", url)
    end
  end

  defp validate_url(url, option) do
    invalid(option, "an http or https URL", url)
  end

  defp validate_locales([_first, _second | _rest] = locales) do
    if different_locales?(locales) do
      :ok
    else
      invalid(:locales, "two or more different locales", locales)
    end
  end

  defp validate_locales(locales) do
    invalid(:locales, "two or more different locales", locales)
  end

  defp validate_regions(nil) do
    :ok
  end

  defp validate_regions([_first, _second] = regions) do
    if different_locales?(regions) do
      :ok
    else
      invalid(:regions, "two different regional locales", regions)
    end
  end

  defp validate_regions(regions) do
    invalid(:regions, "two different regional locales", regions)
  end

  defp different_locales?(locales) do
    Enum.all?(locales, &locale?/1) and Enum.uniq(locales) == locales
  end

  defp locale?(locale) do
    is_binary(locale) and Regex.match?(@locale, locale)
  end

  defp validate_param(param) do
    if is_binary(param) and Regex.match?(@param, param) do
      :ok
    else
      invalid(:param, "a query parameter name", param)
    end
  end

  defp validate_template(nil, _option) do
    :ok
  end

  defp validate_template(template, option) when is_binary(template) do
    if String.contains?(template, @placeholder) do
      validate_url(String.replace(template, @placeholder, "und"), option)
    else
      invalid(option, "a URL template holding {locale}", template)
    end
  end

  defp validate_template(template, option) do
    invalid(option, "a URL template holding {locale}", template)
  end

  defp invalid(option, expected, value) do
    message = "expected #{inspect(option)} to be #{expected}, got: #{inspect(value)}"

    {:error, ArgumentError.exception(message)}
  end
end
