defmodule Mix.Tasks.Cache.Probe do
  @shortdoc "Shows how the cache in front of an application treats vary"

  @moduledoc """
  Plays visitors against a page of your application and reports the
  language each was served and whether the response came from a cache.

      mix cache.probe https://example.com/pricing --locales fr,de

  The page is one whose URL holds no locale. Run it only against an
  application you operate: it sends about 45 `GET` requests, and the
  cache in front of the application may store what comes back.

  The task exits with status 1 when a visitor is served the wrong
  language from a cache, or the cookie stored with another visitor's
  response, or when a visitor's choice of locale is lost to a cache, so
  it can gate a deployment.

  ### Options

  * `--locales` is two or more locales the application supports,
    separated by commas. The first is the locale a browser asks for and
    the second the one a visitor stores. Required.

  * `--param` is the query parameter that chooses a locale. The default
    is `locale`.

  * `--choose-url` is a URL template holding `{locale}`, for an
    application that chooses a locale some other way.

  * `--regions` is two regional locales of one language that the
    application serves differently, such as `fr-FR,fr-CH`. Without it
    the region scenario is skipped.

  * `--localized-url` is a URL template holding `{locale}` for the same
    page with the locale in its URL, such as
    `https://example.com/{locale}/pricing`. Without it the scenario for
    a locale in the URL is skipped.

  """

  use Mix.Task

  alias LocalizeCacheProbe.Report
  alias LocalizeCacheProbe.Scenario
  alias LocalizeCacheProbe.Target

  @switches [
    locales: :string,
    param: :string,
    choose_url: :string,
    regions: :string,
    localized_url: :string
  ]

  @usage "Usage: mix cache.probe URL --locales fr,de [--param locale] [--choose-url TEMPLATE] " <>
           "[--regions fr-FR,fr-CH] [--localized-url TEMPLATE]"

  # A visitor was served something that belongs to someone else, or their
  # choice of locale never reached the application.
  @failures [:wrong_language, :shared_cookie, :choice_lost]

  @impl Mix.Task
  def run(arguments) do
    Mix.Task.run("app.start")

    case probe(arguments) do
      {:ok, report, results} ->
        Mix.shell().info(report)
        exit_on_failure(results)

      {:error, exception} ->
        Mix.raise(Exception.message(exception) <> "\n" <> @usage)
    end
  end

  defp probe(arguments) do
    {options, positional, invalid} = OptionParser.parse(arguments, strict: @switches)

    with {:ok, url} <- url(positional, invalid),
         {:ok, target} <- Target.new(url, target_options(options)),
         {:ok, results} <- Scenario.run_all(target) do
      {:ok, Report.format(target, results), results}
    end
  end

  defp url([url], []) do
    {:ok, url}
  end

  defp url(_positional, [{option, _value} | _rest]) do
    {:error, ArgumentError.exception("unknown option #{option}")}
  end

  defp url(positional, []) do
    {:error, ArgumentError.exception("expected one URL, got: #{inspect(positional)}")}
  end

  defp target_options(options) do
    options
    |> Keyword.take([:param, :choose_url, :localized_url])
    |> Keyword.put(:locales, list(options[:locales]))
    |> Keyword.put(:regions, list(options[:regions]))
  end

  defp list(nil) do
    nil
  end

  defp list(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  defp exit_on_failure(results) do
    if Enum.any?(results, &(&1.verdict in @failures)) do
      exit({:shutdown, 1})
    else
      :ok
    end
  end
end
