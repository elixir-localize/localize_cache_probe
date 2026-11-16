defmodule LocalizeCacheProbe.ReportTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Observation
  alias LocalizeCacheProbe.Report
  alias LocalizeCacheProbe.Target

  doctest LocalizeCacheProbe.Report

  defp step(visitor, accept_language, url, headers) do
    %{
      visitor: visitor,
      accept_language: accept_language,
      url: url,
      observation: Observation.new(200, headers, "")
    }
  end

  test "names the cache, gives its vary note and tabulates each scenario" do
    {:ok, target} = Target.new("https://example.com/pricing", locales: ["fr", "de"])

    result = %{
      name: :stored_locale,
      title: "A visitor with a stored locale",
      verdict: :wrong_language,
      summary: "The visitor who chose de was served the fr page from the cache.",
      steps: [
        step("A", "fr", "https://example.com/pricing", [
          {"content-language", "fr"},
          {"vary", "cookie, accept-language"},
          {"cf-cache-status", "MISS"}
        ]),
        step("B", "fr", "https://example.com/pricing?locale=de", [{"content-language", "de"}]),
        step("B", "fr", "https://example.com/pricing", [
          {"content-language", "fr"},
          {"cf-cache-status", "HIT"}
        ])
      ]
    }

    assert Report.format(target, [result]) ==
             String.trim_trailing("""
             Page:    https://example.com/pricing
             Locales: fr asked for, de stored
             Cache:   cloudflare
                      Ignores vary until a Cache Rule turns it on. The rule can normalise accept-language before the lookup, and its default folds a region into its language.
                      https://blog.cloudflare.com/vary-support/

             1. A visitor with a stored locale
                Verdict: WRONG LANGUAGE
                The visitor who chose de was served the fr page from the cache.

                visitor  asks for  request             status  language  vary                     cache
                A        fr        /pricing            200     fr        cookie, accept-language  miss
                B        fr        /pricing?locale=de  200     de        -                        unknown
                B        fr        /pricing            200     fr        -                        hit
             """)
  end

  test "shows a page with no language, no accept-language and a URL with no path" do
    {:ok, target} = Target.new("https://example.com", locales: ["fr", "de"])

    result = %{
      name: :same_visitor,
      title: "One visitor",
      verdict: :not_reused,
      summary: "Nothing.",
      steps: [step("A", nil, "https://example.com", [{"x-varnish", "32770"}])]
    }

    report = Report.format(target, [result])

    assert report =~ "Cache:   varnish\n"
    assert report =~ "   Verdict: not reused\n"
    assert report =~ "   A        -         /        200     -         -     miss"
  end

  test "says when vary arrived on more than one line" do
    {:ok, target} = Target.new("https://example.com/", locales: ["fr", "de"])
    headers = [{"vary", "accept-language"}, {"vary", "Accept-Encoding"}]

    result = %{
      name: :same_visitor,
      title: "One visitor",
      verdict: :reused,
      summary: "Reused.",
      steps: [step("A", "fr", "https://example.com/", headers)]
    }

    assert Report.format(target, [result]) =~ "accept-language, accept-encoding (2 lines)"
  end

  test "prints a skipped scenario with no table, and the two serious verdicts in capitals" do
    {:ok, target} = Target.new("https://example.com/", locales: ["fr", "de"])

    results = [
      %{name: :region, title: "Regions", verdict: :skipped, summary: "Give two.", steps: []},
      %{name: :first_visit, title: "Cookies", verdict: :shared_cookie, summary: "Bad.", steps: []}
    ]

    assert Report.format(target, results) ==
             String.trim_trailing("""
             Page:    https://example.com/
             Locales: fr asked for, de stored
             Cache:   not recognised

             1. Regions
                Verdict: skipped
                Give two.

             2. Cookies
                Verdict: SHARED COOKIE
                Bad.
             """)
  end
end
