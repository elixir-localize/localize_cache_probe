defmodule LocalizeCacheProbe.ScenarioTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Scenario
  alias LocalizeCacheProbe.Target
  alias LocalizeCacheProbe.TestApplication
  alias LocalizeCacheProbe.TestOrigin

  doctest LocalizeCacheProbe.Scenario

  defp application_target(cache) do
    url = TestApplication.start(cache)

    {:ok, target} =
      Target.new(url <> "/pricing",
        locales: ["fr", "de"],
        regions: ["fr-FR", "fr-CH"],
        localized_url: url <> "/{locale}/pricing"
      )

    target
  end

  defp page(language, headers \\ []) do
    TestOrigin.response(
      200,
      [{"Content-Language", language} | headers],
      "<html lang=\"#{language}\">"
    )
  end

  defp target(responses) do
    url = TestOrigin.start(responses)
    {:ok, target} = Target.new(url <> "/pricing", locales: ["fr", "de"])

    target
  end

  defp requests(result) do
    for _step <- result.steps do
      assert_receive {:request, request}
      request
    end
  end

  describe "the stored-locale scenario" do
    test "is :correct when the visitor is served the locale they chose" do
      target =
        target([
          page("fr", [{"Vary", "cookie, accept-language"}, {"Set-Cookie", "s=a; path=/"}]),
          page("fr", [{"Vary", "cookie"}]),
          page("de", [{"Set-Cookie", "s=b; path=/"}]),
          page("de", [{"Vary", "cookie"}]),
          page("de", [{"Vary", "cookie"}])
        ])

      assert {:ok, result} = Scenario.run(:stored_locale, target)
      assert result.verdict == :correct
      assert result.name == :stored_locale
      assert Enum.map(result.steps, & &1.visitor) == ["A", "A", "B", "B", "B"]
      assert Enum.map(result.steps, & &1.observation.language) == ["fr", "fr", "de", "de", "de"]

      [first, again, chosen, control, served] = requests(result)

      assert first =~ "GET /pricing HTTP/1.1"
      assert first =~ ~r/accept-language: fr\r\n/i
      refute first =~ ~r/\r\ncookie:/i

      assert again =~ "GET /pricing HTTP/1.1"
      assert again =~ ~r/\r\ncookie: s=a\r\n/i

      assert chosen =~ "GET /pricing?locale=de HTTP/1.1"
      refute chosen =~ ~r/\r\ncookie:/i

      assert control =~ ~r{GET /pricing\?_probe=\d+ HTTP/1\.1}
      assert control =~ ~r/\r\ncookie: s=b\r\n/i

      assert served =~ "GET /pricing HTTP/1.1"
      assert served =~ ~r/\r\ncookie: s=b\r\n/i
    end

    test "is :wrong_language when the page differs from the control, with or without a cache header" do
      for headers <- [[{"Age", "5"}], []] do
        target = target([page("fr"), page("fr"), page("de"), page("de"), page("fr", headers)])

        assert {:ok, result} = Scenario.run(:stored_locale, target)
        assert result.verdict == :wrong_language
        assert result.summary =~ "was served fr at the page, and de at a URL no cache had seen"
      end
    end

    test "is :wrong_language when the page is in a third language or in none" do
      target = target([page("fr"), page("fr"), page("de"), page("de"), page("en")])

      assert {:ok, %{verdict: :wrong_language, summary: summary}} =
               Scenario.run(:stored_locale, target)

      assert summary =~ "was served en at the page"

      plain = TestOrigin.response(200, [], "no language here")
      target = target([page("fr"), page("fr"), page("de"), page("de"), plain])

      assert {:ok, %{verdict: :wrong_language, summary: summary}} =
               Scenario.run(:stored_locale, target)

      assert summary =~ "a page with no language"
    end

    test "is :skipped when the application itself does not serve the chosen locale" do
      target =
        target([page("fr"), page("fr"), page("de"), page("fr"), page("fr", [{"Age", "5"}])])

      assert {:ok, %{verdict: :skipped, summary: summary}} = Scenario.run(:stored_locale, target)
      assert summary =~ "it does not store the choice"
    end

    test "takes a more specific locale as a match" do
      target = target([page("fr-CA"), page("fr-CA"), page("de"), page("de-CH"), page("de-CH")])

      assert {:ok, %{verdict: :correct}} = Scenario.run(:stored_locale, target)
    end
  end

  describe "the other-language scenario" do
    test "sends each browser's own accept-language, no cookie, and a control request" do
      target = target([page("fr", [{"Set-Cookie", "s=a; path=/"}]), page("de"), page("de")])

      assert {:ok, result} = Scenario.run(:other_language, target)
      assert result.verdict == :correct

      assert Enum.map(result.steps, &{&1.visitor, &1.accept_language}) ==
               [{"A", "fr"}, {"C", "de"}, {"D", "de"}]

      [first, second, control] = requests(result)

      assert first =~ ~r/accept-language: fr\r\n/i

      assert second =~ "GET /pricing HTTP/1.1"
      assert second =~ ~r/accept-language: de\r\n/i
      refute second =~ ~r/\r\ncookie:/i

      assert control =~ ~r{GET /pricing\?_probe=\d+ HTTP/1\.1}
      assert control =~ ~r/accept-language: de\r\n/i
      refute control =~ ~r/\r\ncookie:/i
    end

    test "is :wrong_language when the second visitor is served the first one's page" do
      target = target([page("fr"), page("fr", [{"X-Cache", "HIT"}]), page("de")])

      assert {:ok, %{verdict: :wrong_language}} = Scenario.run(:other_language, target)
    end

    test "is :skipped when the application does not read the header" do
      target = target([page("fr"), page("fr"), page("fr")])

      assert {:ok, %{verdict: :skipped, summary: summary}} =
               Scenario.run(:other_language, target)

      assert summary =~ "it may not read accept-language"
    end
  end

  describe "the same-visitor scenario" do
    test "is :reused when the third request is a hit" do
      target =
        target([
          page("fr", [{"Set-Cookie", "s=a; path=/"}]),
          page("fr", [{"X-Cache", "MISS"}]),
          page("fr", [{"X-Cache", "HIT"}])
        ])

      assert {:ok, result} = Scenario.run(:same_visitor, target)
      assert result.verdict == :reused
      assert length(result.steps) == 3

      [_first, second, _third] = requests(result)
      assert second =~ ~r/\r\ncookie: s=a\r\n/i
    end

    test "is :not_cached when the response is private or the cache refuses it" do
      private = page("fr", [{"Cache-Control", "max-age=0, private, must-revalidate"}])

      assert {:ok, %{verdict: :not_cached, summary: summary}} =
               Scenario.run(:same_visitor, target([private, private, private]))

      assert summary =~ "private"

      refused = page("fr", [{"CF-Cache-Status", "DYNAMIC"}])

      assert {:ok, %{verdict: :not_cached}} =
               Scenario.run(:same_visitor, target([refused, refused, refused]))
    end

    test "is :not_reused when nothing shows a hit" do
      public = page("fr", [{"Cache-Control", "public, max-age=60"}])

      assert {:ok, %{verdict: :not_reused}} =
               Scenario.run(:same_visitor, target([public, public, public]))
    end
  end

  describe "the header-form scenario" do
    test "sends a longer header that selects the same locale, with the same cookie" do
      target = application_target(:honours_vary)

      assert {:ok, result} = Scenario.run(:header_form, target)

      assert Enum.map(result.steps, & &1.accept_language) == ["fr", "fr", "fr", "fr,*;q=0.1"]
      assert Enum.map(result.steps, & &1.observation.language) == ["fr", "fr", "fr", "fr"]

      last = List.last(requests(result))
      assert last =~ ~r/accept-language: fr,\*;q=0\.1\r\n/i
      assert last =~ ~r/\r\ncookie: s=fr\.1\r\n/i
    end
  end

  describe "against a model application" do
    # The verdict of each scenario for an application with no cache,
    # behind a cache that honours `vary`, and behind one that keys on the
    # path alone.
    @verdicts %{
      none: [
        other_language: :correct,
        stored_locale: :correct,
        same_visitor: :not_reused,
        two_visitors: :not_reused,
        header_form: :not_reused,
        region: :correct,
        url_locale: :not_reused,
        first_visit: :not_reused
      ],
      # Once the session holds the locale it decides, so `vary` names
      # only the cookie and a longer accept-language is served the copy.
      honours_vary: [
        other_language: :correct,
        stored_locale: :correct,
        same_visitor: :reused,
        two_visitors: :not_shared,
        header_form: :shared,
        region: :correct,
        url_locale: :shared,
        first_visit: :not_reused
      ],
      # This cache replays the cookie it stored with the first response, so
      # both visitors end up holding it and cannot be told apart.
      ignores_vary: [
        other_language: :wrong_language,
        stored_locale: :wrong_language,
        same_visitor: :reused,
        two_visitors: :skipped,
        header_form: :shared,
        region: :wrong_language,
        url_locale: :shared,
        first_visit: :shared_cookie
      ]
    }

    for {cache, verdicts} <- @verdicts do
      test "each scenario alone, with the cache #{inspect(cache)}" do
        assert Keyword.keys(unquote(verdicts)) == Scenario.names()

        for {name, verdict} <- unquote(verdicts) do
          assert {:ok, result} = Scenario.run(name, application_target(unquote(cache)))
          assert {name, result.verdict} == {name, verdict}
        end
      end

      # A later scenario starts from the pages an earlier one left in the
      # cache. The control request keeps the verdicts the same.
      test "every scenario in turn against one application, with the cache #{inspect(cache)}" do
        assert {:ok, results} = Scenario.run_all(application_target(unquote(cache)))
        assert Enum.map(results, &{&1.name, &1.verdict}) == unquote(verdicts)
      end
    end

    test "the url-locale scenario requests the localized URL while asking for another locale" do
      assert {:ok, result} = Scenario.run(:url_locale, application_target(:honours_vary))

      assert Enum.map(result.steps, & &1.visitor) == ["A", "A", "C", "C", "C"]
      assert Enum.all?(result.steps, &String.ends_with?(&1.url, "/de/pricing"))
      assert Enum.all?(result.steps, &(&1.accept_language == "fr"))
      assert Enum.all?(result.steps, &(&1.observation.language == "de"))
      assert List.last(result.steps).observation.vary == []
    end

    test "the region scenario sends each region as accept-language" do
      assert {:ok, result} = Scenario.run(:region, application_target(:none))

      assert Enum.map(result.steps, & &1.accept_language) == ["fr-FR", "fr-CH", "fr-CH"]
      assert Enum.map(result.steps, & &1.observation.language) == ["fr-fr", "fr-ch", "fr-ch"]
    end
  end

  describe "scenarios that need more than a page and two locales" do
    test "are :skipped without the option they need" do
      target = target([])

      assert {:ok, %{verdict: :skipped, steps: [], summary: region}} =
               Scenario.run(:region, target)

      assert region =~ "regional locales"

      assert {:ok, %{verdict: :skipped, steps: [], summary: url}} =
               Scenario.run(:url_locale, target)

      assert url =~ "template"

      refute_receive {:request, _request}, 50
    end

    test "the url-locale scenario is :inconclusive when the localized page is in another language" do
      url = TestOrigin.start(List.duplicate(page("fr"), 5))

      {:ok, target} =
        Target.new(url <> "/pricing",
          locales: ["fr", "de"],
          localized_url: url <> "/{locale}/pricing"
        )

      assert {:ok, %{verdict: :inconclusive, summary: summary}} =
               Scenario.run(:url_locale, target)

      assert summary =~ "was not served in de"
    end
  end

  describe "the first-visit scenario" do
    defp cookie(value, headers \\ []) do
      page("fr", [{"Set-Cookie", "s=#{value}; path=/"} | headers])
    end

    test "makes a control request as a third new visitor" do
      target = target([cookie("a"), cookie("b"), cookie("c")])

      assert {:ok, result} = Scenario.run(:first_visit, target)
      assert Enum.map(result.steps, & &1.visitor) == ["A", "C", "D"]

      [first, second, control] = requests(result)

      assert first =~ "GET /pricing HTTP/1.1"
      assert second =~ "GET /pricing HTTP/1.1"
      assert control =~ ~r{GET /pricing\?_probe=\d+ HTTP/1\.1}
      refute Enum.any?([first, second, control], &(&1 =~ ~r/\r\ncookie:/i))
    end

    test "is :skipped when the first response sets no cookie" do
      assert {:ok, %{verdict: :skipped}} =
               Scenario.run(:first_visit, target([page("fr"), page("fr"), page("fr")]))
    end

    test "is :reused when the second visitor is served from the cache without the cookie" do
      target = target([cookie("a"), page("fr", [{"Age", "3"}]), cookie("c")])

      assert {:ok, %{verdict: :reused, summary: summary}} = Scenario.run(:first_visit, target)
      assert summary =~ "without the first visitor's cookie"
    end

    test "is :shared_cookie when the cache replays a cookie the application gives one visitor" do
      target = target([cookie("a"), cookie("a", [{"Age", "3"}]), cookie("c")])

      assert {:ok, %{verdict: :shared_cookie, summary: summary}} =
               Scenario.run(:first_visit, target)

      assert summary =~ "share a session"
    end

    test "is :reused when the application gives every visitor the same cookie" do
      target = target([cookie("a"), cookie("a", [{"Age", "3"}]), cookie("a")])

      assert {:ok, %{verdict: :reused, summary: summary}} = Scenario.run(:first_visit, target)
      assert summary =~ "every visitor alike"
    end

    test "is :not_reused when each new visitor is given a cookie of their own" do
      target = target([cookie("a"), cookie("b"), cookie("c")])

      assert {:ok, %{verdict: :not_reused}} = Scenario.run(:first_visit, target)
    end
  end

  describe "the two-visitor scenario" do
    test "is :skipped when both visitors hold the same cookie" do
      hit = page("fr", [{"X-Cache", "HIT"}])
      same = page("fr", [{"Set-Cookie", "s=fr; path=/"}])

      assert {:ok, %{verdict: :skipped, summary: summary, steps: steps}} =
               Scenario.run(:two_visitors, target([same, hit, same, hit, hit]))

      assert summary =~ "Both visitors hold the same cookie"
      assert length(steps) == 5
    end

    test "is :skipped when neither visitor is given a cookie" do
      hit = page("fr", [{"X-Cache", "HIT"}])

      assert {:ok, %{verdict: :skipped, summary: summary}} =
               Scenario.run(:two_visitors, target(List.duplicate(hit, 5)))

      assert summary =~ "Neither visitor was given a cookie"
    end

    test "judges the cache when the two hold different cookies" do
      hit = page("fr", [{"X-Cache", "HIT"}])
      miss = page("fr", [{"X-Cache", "MISS"}])
      first = page("fr", [{"Set-Cookie", "s=1; path=/"}])
      second = page("fr", [{"Set-Cookie", "s=2; path=/"}])

      assert {:ok, %{verdict: :shared, summary: summary}} =
               Scenario.run(:two_visitors, target([first, miss, second, hit, hit]))

      assert summary =~ "with a cookie of their own"

      assert {:ok, %{verdict: :not_shared}} =
               Scenario.run(:two_visitors, target([first, miss, second, miss, hit]))
    end
  end

  describe "the url-locale scenario" do
    defp localized_target(responses) do
      url = TestOrigin.start(responses)

      {:ok, target} =
        Target.new(url <> "/pricing",
          locales: ["fr", "de"],
          localized_url: url <> "/{locale}/pricing"
        )

      target
    end

    test "says so when a shared page was shared by two visitors with the same cookies" do
      hit = page("de", [{"X-Cache", "HIT"}])

      assert {:ok, %{verdict: :shared, summary: summary}} =
               Scenario.run(:url_locale, localized_target(List.duplicate(hit, 5)))

      assert summary =~ "The two hold the same cookies"
    end

    test "is plainly :shared when the two hold different cookies" do
      hit = page("de", [{"X-Cache", "HIT"}])
      first = page("de", [{"Set-Cookie", "s=1; path=/"}])
      second = page("de", [{"Set-Cookie", "s=2; path=/"}])

      assert {:ok, %{verdict: :shared, summary: summary}} =
               Scenario.run(:url_locale, localized_target([first, hit, second, hit, hit]))

      assert summary =~ "with a cookie of their own"
    end
  end

  describe "run_all/1" do
    test "returns the error of a request that cannot be made" do
      {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, port} = :inet.port(listen)
      :ok = :gen_tcp.close(listen)
      {:ok, target} = Target.new("http://127.0.0.1:#{port}/", locales: ["fr", "de"])

      assert {:error, %Mint.TransportError{}} = Scenario.run_all(target)
      assert {:error, %Mint.TransportError{}} = Scenario.run(:same_visitor, target)
    end
  end
end
