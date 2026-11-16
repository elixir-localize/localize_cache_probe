defmodule LocalizeCacheProbe.Scenario do
  @moduledoc """
  The situations the probe plays against an application, and the verdict
  it reaches on each.

  The primary API is `names/0`, `run/2` and `run_all/1`. A scenario
  makes a few requests as one or two visitors, and compares what each
  was served.

  * `:other_language` — visitor A's browser asks for one locale and
    visitor C's for another. A cache that takes no account of
    `accept-language` serves C the page made for A.

  * `:stored_locale` — visitor A's browser asks for one locale and their
    page is requested first. Visitor B has chosen another locale, which
    the application stored, and then requests the same page. A cache
    that takes no account of the cookie serves B the page made for A.

  * `:same_visitor` — one visitor requests the page three times. This is
    what a developer sees when checking a cache in one browser, where
    the cookie never changes.

  * `:two_visitors` — two visitors whose browsers ask for the same
    locale, each with a cookie of their own. It shows whether the cache
    serves both from one copy or keeps a copy for each.

  * `:header_form` — one visitor sends `accept-language` in a short form
    and then a longer form that means the same. It shows whether each
    form of the header gets a copy of its own.

  * `:region` — two visitors whose browsers ask for different regions of
    one language, such as `fr-FR` and `fr-CH`. A cache that folds a
    region into its language serves the second the first one's page. It
    is skipped unless the target names two regions.

  * `:url_locale` — the two-visitor requests against the page with a
    locale in its URL, where no request header decides. It is skipped
    unless the target has a localized URL.

  * `:first_visit` — two new visitors, neither with a cookie. It shows
    whether the cache serves the second from the copy made for the first,
    and where the first response sets a cookie, whether the cache then
    hands that cookie to someone else.

  * `:vary_lines` — a response may carry its `vary` on several header
    lines, and a cache has to read them all. The scenario repeats the
    checks on `accept-language` and on the cookie, and reports each
    against the line that named it. It is skipped unless a response
    reaches the probe with one of those fields among two or more lines,
    which a cache that joins the lines prevents.

  * `:second_choice` — two visitors choose a locale through the same
    URL, one after the other. A cache that stores the page which stores
    a choice serves it to the second visitor, and if it leaves the
    cookie out, as it should, their choice is never stored.

  """

  alias LocalizeCacheProbe.Observation
  alias LocalizeCacheProbe.Target
  alias LocalizeCacheProbe.Visitor

  @names [
    :other_language,
    :stored_locale,
    :same_visitor,
    :two_visitors,
    :header_form,
    :region,
    :url_locale,
    :first_visit,
    :vary_lines,
    :second_choice
  ]

  @titles %{
    other_language: "Two visitors whose browsers ask for different locales",
    stored_locale: "A visitor with a stored locale, after another visitor's page is cached",
    same_visitor: "One visitor, three requests",
    two_visitors: "Two visitors who ask for the same locale, each with a cookie of their own",
    header_form: "One visitor, two forms of the same accept-language",
    region: "Two visitors whose browsers ask for different regions of one language",
    url_locale: "Two visitors at the page with a locale in its URL",
    first_visit: "Two new visitors, neither with a cookie",
    vary_lines: "A response whose vary is on more than one line",
    second_choice: "Two visitors who choose a locale through the same URL"
  }

  # A response with any of these may not be reused from a shared cache.
  @unshared_directives ["private", "no-store", "no-cache"]

  # Added to a locale to make a header that differs as text and selects
  # the same locale: the wildcard at a low quality changes no best match.
  @longer_form ",*;q=0.1"

  # The query parameter of a control request. Its value is new each time.
  @control_param "_probe"

  @typedoc """
  The verdict of a scenario.

  * `:correct` — each visitor was served the locale they should be.

  * `:wrong_language` — a cache served one visitor the page made for
    another.

  * `:reused` — a repeated request was served from a cache.

  * `:not_reused` — nothing shows a repeated request served from a cache.

  * `:not_cached` — the response is kept out of shared caches.

  * `:shared` — a request that differs from the one a page was stored
    for was served from the cache.

  * `:not_shared` — the cache reuses a page only for a request like the
    one it was stored for.

  * `:shared_cookie` — a cache gave one new visitor the cookie it had
    stored with another's response.

  * `:choice_lost` — a visitor chose a locale and the application was
    never told, because a cache answered in its place.

  * `:skipped` — the scenario was not run, or had nothing to test.

  * `:inconclusive` — the responses do not settle the question.

  """
  @type verdict ::
          :correct
          | :wrong_language
          | :reused
          | :not_reused
          | :not_cached
          | :shared
          | :not_shared
          | :shared_cookie
          | :choice_lost
          | :skipped
          | :inconclusive

  @typedoc "One request of a scenario and what came back."
  @type step :: %{
          visitor: String.t(),
          accept_language: String.t() | nil,
          url: String.t(),
          observation: Observation.t()
        }

  @typedoc "A scenario's outcome: its verdict, a sentence on why, and its steps."
  @type result :: %{
          name: atom(),
          title: String.t(),
          verdict: verdict(),
          summary: String.t(),
          steps: [step()]
        }

  @doc """
  Returns the names of the scenarios, in the order they are run.

  ### Returns

  * A list of scenario names.

  ### Examples

      iex> Enum.take(LocalizeCacheProbe.Scenario.names(), 3)
      [:other_language, :stored_locale, :same_visitor]

  """
  @spec names() :: [atom()]
  def names do
    @names
  end

  @doc """
  Runs one scenario against a target.

  ### Arguments

  * `name` is one of `names/0`.

  * `target` is a `t:LocalizeCacheProbe.Target.t/0`.

  ### Returns

  * `{:ok, result}` where `result` is a `t:result/0`, or

  * `{:error, exception}` when the name is not a scenario or a request
    could not be made.

  ### Examples

      iex> {:ok, target} = LocalizeCacheProbe.Target.new("http://example.com/", locales: ["fr", "de"])
      iex> {:error, exception} = LocalizeCacheProbe.Scenario.run(:no_such, target)
      iex> Exception.message(exception)
      "unknown scenario :no_such"

  """
  @spec run(atom(), Target.t()) :: {:ok, result()} | {:error, Exception.t()}
  def run(:other_language, %Target{locales: [asked, other | _rest]} = target) do
    hint = "it may not read accept-language"

    two_browsers(:other_language, target.url, asked, other, hint)
  end

  def run(:stored_locale, %Target{locales: [asked, stored | _rest]} = target) do
    with {:ok, {verdict, summary}, steps} <- stored_check(target, asked, stored) do
      {:ok, result(:stored_locale, verdict, summary, steps)}
    end
  end

  def run(:same_visitor, %Target{locales: [asked | _rest]} = target) do
    visitor = Visitor.new("A", accept_language: asked)

    with {:ok, _visitor, steps} <- visits(visitor, target.url, 3, []) do
      {verdict, summary} = same_visitor_verdict(List.last(steps).observation)

      {:ok, result(:same_visitor, verdict, summary, steps)}
    end
  end

  def run(:two_visitors, %Target{locales: [asked | _rest]} = target) do
    with {:ok, cookies, steps} <- two_visitors(target.url, asked) do
      [second, third] = Enum.take(steps, -2)
      {verdict, summary} = two_visitors_verdict(cookies, second.observation, third.observation)

      {:ok, result(:two_visitors, verdict, summary, steps)}
    end
  end

  def run(:header_form, %Target{locales: [asked | _rest]} = target) do
    visitor = Visitor.new("A", accept_language: asked)

    with {:ok, visitor, short} <- visits(visitor, target.url, 3, []),
         longer = %{visitor | accept_language: asked <> @longer_form},
         {:ok, _visitor, long} <- step(longer, target.url) do
      {verdict, summary} = header_form_verdict(List.last(short).observation, long.observation)

      {:ok, result(:header_form, verdict, summary, short ++ [long])}
    end
  end

  def run(:region, %Target{regions: nil}) do
    {:ok, skipped(:region, "Give two regional locales the application serves differently.")}
  end

  def run(:region, %Target{regions: [first, second]} = target) do
    hint = "it may not tell the two regions apart"

    two_browsers(:region, target.url, first, second, hint)
  end

  def run(:url_locale, %Target{locales: [asked, other | _rest]} = target) do
    case Target.localized_url(target, other) do
      {:ok, url} ->
        url_locale(url, asked, other)

      :error ->
        {:ok, skipped(:url_locale, "Give a template for the page's URL with a locale in it.")}
    end
  end

  def run(:first_visit, %Target{locales: [asked | _rest]} = target) do
    # The third visitor's request is the control: a URL no cache has
    # stored, so the cookie they are given comes from the application.
    with {:ok, first, primed} <- step(Visitor.new("A", accept_language: asked), target.url),
         {:ok, second, served} <- step(Visitor.new("C", accept_language: asked), target.url),
         {:ok, third, control} <-
           step(Visitor.new("D", accept_language: asked), unseen_url(target.url)) do
      facts = {
        primed.observation.set_cookie?,
        served.observation.cache_status == :hit,
        cookies(first, second) == :same,
        cookies(first, third) == :same
      }

      {verdict, summary} = first_visit_verdict(facts)

      {:ok, result(:first_visit, verdict, summary, [primed, served, control])}
    end
  end

  def run(:vary_lines, %Target{locales: [asked, other | _rest]} = target) do
    hint = "it may not read accept-language"

    with {:ok, header, header_steps} <- browsers_check(target.url, asked, other, hint),
         {:ok, cookie, cookie_steps} <- stored_check(target, asked, other) do
      checks = [{"accept-language", header, header_steps}, {"cookie", cookie, cookie_steps}]
      {verdict, summary} = vary_lines_verdict(Enum.flat_map(checks, &line_check/1))

      {:ok, result(:vary_lines, verdict, summary, header_steps ++ cookie_steps)}
    end
  end

  def run(:second_choice, %Target{locales: [asked, chosen | _rest]} = target) do
    # Both visitors choose through one URL, which nothing has requested
    # before the first of them does.
    choose_url = unseen_url(Target.choose_url(target, chosen))

    with {:ok, first, first_steps} <-
           choice(Visitor.new("A", accept_language: asked), choose_url, target),
         {:ok, second, second_steps} <-
           choice(Visitor.new("B", accept_language: asked), choose_url, target) do
      facts = {language?(first, chosen), language?(second, chosen)}
      {verdict, summary} = second_choice_verdict(facts, chosen)

      {:ok, result(:second_choice, verdict, summary, first_steps ++ second_steps)}
    end
  end

  def run(name, %Target{}) do
    {:error, ArgumentError.exception("unknown scenario #{inspect(name)}")}
  end

  @doc """
  Runs every scenario against a target, in the order of `names/0`.

  ### Arguments

  * `target` is a `t:LocalizeCacheProbe.Target.t/0`.

  ### Returns

  * `{:ok, results}` where `results` is a list of `t:result/0`, or

  * `{:error, exception}` from the first request that could not be made.

  ### Examples

      iex> {:ok, target} = LocalizeCacheProbe.Target.new("http://localhost:1/", locales: ["fr", "de"])
      iex> {:error, %Mint.TransportError{}} = LocalizeCacheProbe.Scenario.run_all(target)

  """
  @spec run_all(Target.t()) :: {:ok, [result()]} | {:error, Exception.t()}
  def run_all(%Target{} = target) do
    run_each(@names, target, [])
  end

  defp run_each([], _target, results) do
    {:ok, Enum.reverse(results)}
  end

  defp run_each([name | rest], target, results) do
    with {:ok, result} <- run(name, target) do
      run_each(rest, target, [result | results])
    end
  end

  defp step(visitor, url) do
    with {:ok, visited, observation} <- Visitor.visit(visitor, url) do
      step = %{
        visitor: visitor.name,
        accept_language: visitor.accept_language,
        url: url,
        observation: observation
      }

      {:ok, visited, step}
    end
  end

  # One visitor requesting one URL several times, keeping their cookies.
  defp visits(visitor, _url, 0, steps) do
    {:ok, visitor, Enum.reverse(steps)}
  end

  defp visits(visitor, url, count, steps) do
    with {:ok, visitor, step} <- step(visitor, url) do
      visits(visitor, url, count - 1, [step | steps])
    end
  end

  # A requests the page twice, so that a copy is stored for a request
  # that carries their cookie. C then requests it three times: the first
  # gives C a cookie, the second shows whether A's copy is reused for C,
  # and the third whether C's own copy is.
  defp two_visitors(url, accept_language) do
    first = Visitor.new("A", accept_language: accept_language)
    second = Visitor.new("C", accept_language: accept_language)

    with {:ok, first, primed} <- visits(first, url, 2, []),
         {:ok, second, served} <- visits(second, url, 3, []) do
      {:ok, cookies(first, second), primed ++ served}
    end
  end

  # Whether two visitors can be told apart by the cookies they hold. Two
  # who hold the same cookies, or none, send the same request, and a
  # cache that serves both from one copy has shown nothing about cookies.
  defp cookies(%Visitor{cookies: first}, %Visitor{cookies: second})
       when map_size(first) == 0 and map_size(second) == 0 do
    :none
  end

  defp cookies(%Visitor{cookies: cookies}, %Visitor{cookies: cookies}) do
    :same
  end

  defp cookies(%Visitor{}, %Visitor{}) do
    :different
  end

  # Two new visitors whose browsers ask for different locales, the first
  # of them requesting the page before the second. A third, whose
  # browser asks for what the second one's does, makes the control
  # request: a new visitor, so that no cookie from the page decides.
  defp two_browsers(name, url, first_locale, second_locale, hint) do
    with {:ok, {verdict, summary}, steps} <-
           browsers_check(url, first_locale, second_locale, hint) do
      {:ok, result(name, verdict, summary, steps)}
    end
  end

  # The requests of `two_browsers/5` and their outcome, for a scenario to
  # report as its own or to combine with another's. This is the check on
  # `accept-language`: neither visitor has a cookie, so it alone decides.
  defp browsers_check(url, first_locale, second_locale, hint) do
    first = Visitor.new("A", accept_language: first_locale)
    second = Visitor.new("C", accept_language: second_locale)
    third = Visitor.new("D", accept_language: second_locale)

    with {:ok, _first, primed} <- step(first, url),
         {:ok, _second, served} <- step(second, url),
         {:ok, _third, control} <- step(third, unseen_url(url)) do
      labels = %{
        who: "The visitor whose browser asked for #{second_locale}",
        wanted: second_locale,
        hint: hint
      }

      outcome = page_verdict(control.observation, served.observation, labels)

      {:ok, outcome, [primed, served, control]}
    end
  end

  # The check on the cookie: one visitor's page is requested first, and
  # another, who has chosen a different locale, requests it after.
  defp stored_check(target, asked, stored) do
    first = Visitor.new("A", accept_language: asked)
    second = Visitor.new("B", accept_language: asked)

    # A requests the page twice: a cache that will not store the response
    # that sets A's cookie can store the one after it.
    with {:ok, _first, primed} <- visits(first, target.url, 2, []),
         {:ok, second, chosen} <- step(second, unseen_url(Target.choose_url(target, stored))),
         {:ok, second, control} <- step(second, unseen_url(target.url)),
         {:ok, _second, served} <- step(second, target.url) do
      labels = %{
        who: "The visitor who chose #{stored}",
        wanted: stored,
        hint: "it does not store the choice, or the choose URL is wrong"
      }

      outcome = page_verdict(control.observation, served.observation, labels)

      {:ok, outcome, primed ++ [chosen, control, served]}
    end
  end

  # A visitor chooses a locale, then asks for the page at a URL no cache
  # has stored. The second observation is what the application serves
  # them, which is the chosen locale only if the choice was stored.
  defp choice(visitor, choose_url, target) do
    with {:ok, visitor, chosen} <- step(visitor, choose_url),
         {:ok, _visitor, control} <- step(visitor, unseen_url(target.url)) do
      {:ok, control.observation, [chosen, control]}
    end
  end

  defp second_choice_verdict({false, _second?}, chosen) do
    {:skipped,
     "The application did not serve #{chosen} to the first visitor who chose it: it does " <>
       "not store the choice, or the choose URL is wrong."}
  end

  defp second_choice_verdict({true, true}, chosen) do
    {:correct, "Each visitor who chose #{chosen} was served #{chosen} afterwards."}
  end

  defp second_choice_verdict({true, false}, chosen) do
    {:choice_lost,
     "The first visitor who chose #{chosen} was remembered and the second was not. The page " <>
       "that stores a choice was stored itself, and the second visitor was served it " <>
       "without a cookie of their own."}
  end

  # Where a field is named among the `vary` lines of a response that has
  # two or more of them: the number of its line and how many there are.
  defp vary_line(field, steps) do
    steps
    |> Enum.map(& &1.observation.vary_by_line)
    |> Enum.find_value(&line_of(field, &1))
  end

  defp line_of(field, [_first, _second | _rest] = lines) do
    index = Enum.find_index(lines, &(field in &1))

    if is_nil(index) do
      nil
    else
      {index + 1, length(lines)}
    end
  end

  defp line_of(_field, _lines) do
    nil
  end

  # One entry for each field that was named among several `vary` lines,
  # with the outcome of the check on that field.
  defp line_check({field, {verdict, _summary}, steps}) do
    case vary_line(field, steps) do
      {line, lines} -> [%{field: field, line: line, lines: lines, verdict: verdict}]
      nil -> []
    end
  end

  defp vary_lines_verdict([]) do
    {:skipped,
     "No response reached the probe with accept-language or cookie named among two or more " <>
       "vary lines. A cache may join the lines before it sends them on."}
  end

  defp vary_lines_verdict([_ | _] = checks) do
    failed = Enum.find(checks, &(&1.verdict == :wrong_language))
    passed = Enum.filter(checks, &(&1.verdict == :correct))
    untested = Enum.filter(checks, &(&1.verdict == :skipped))

    vary_lines_outcome(failed, passed, untested)
  end

  defp vary_lines_outcome(%{} = failed, _passed, _untested) do
    {:wrong_language,
     "The cache did not honour #{failed.field}, which arrived on " <> position(failed) <> "."}
  end

  defp vary_lines_outcome(nil, [], _untested) do
    {:skipped,
     "The fields arrived on several vary lines, but the application did not serve the " <>
       "locales needed to test them."}
  end

  defp vary_lines_outcome(nil, [_ | _] = passed, untested) do
    honoured = Enum.map_join(passed, " and ", &"#{&1.field}, on #{position(&1)}")

    {:correct, "The cache honoured #{honoured}." <> untested_note(untested)}
  end

  # A field that arrived among several lines and could not be tested is
  # named, so that a verdict of correct is not read as covering it.
  defp untested_note([]) do
    ""
  end

  defp untested_note([_ | _] = untested) do
    fields = Enum.map_join(untested, " and ", & &1.field)

    " It could not test #{fields}: the application did not serve the locale needed."
  end

  defp position(%{line: line, lines: lines}) do
    "line #{line} of #{lines} vary lines"
  end

  # A URL with a parameter no request has carried before, so that a cache
  # has nothing stored for it and the application answers. It makes a
  # control request out of the page's URL, and gives a scenario a choose
  # URL that no earlier scenario has left in the cache.
  defp unseen_url(url) do
    unique = System.unique_integer([:positive, :monotonic])
    token = Integer.to_string(System.system_time(:microsecond)) <> Integer.to_string(unique)

    url
    |> URI.parse()
    |> URI.append_query(@control_param <> "=" <> token)
    |> URI.to_string()
  end

  # The two-visitor requests against the page with a locale in its URL.
  # Both browsers ask for another locale, so the URL alone decides.
  defp url_locale(url, asked, locale) do
    with {:ok, cookies, steps} <- two_visitors(url, asked) do
      [second, third] = Enum.take(steps, -2)

      {verdict, summary} =
        if language?(second.observation, locale) do
          qualify(sharing_verdict(second.observation, third.observation), cookies)
        else
          {:inconclusive, "The page with #{locale} in its URL was not served in #{locale}."}
        end

      {:ok, result(:url_locale, verdict, summary, steps)}
    end
  end

  defp skipped(name, summary) do
    result(name, :skipped, summary, [])
  end

  # A page no request header decides is shared whatever cookies the two
  # visitors hold, but only two who hold different ones show that the
  # cache disregards a cookie.
  defp qualify({:shared, _summary}, cookies) when cookies in [:none, :same] do
    {:shared,
     "A second visitor was served from the cache. The two hold the same cookies, so this " <>
       "does not show the cache disregarding a cookie."}
  end

  defp qualify(outcome, _cookies) do
    outcome
  end

  defp two_visitors_verdict(:different, other, own) do
    sharing_verdict(other, own)
  end

  defp two_visitors_verdict(:none, _other, _own) do
    {:skipped,
     "Neither visitor was given a cookie, so the two send the same request and cannot be " <>
       "told apart."}
  end

  defp two_visitors_verdict(:same, _other, _own) do
    {:skipped,
     "Both visitors hold the same cookie, so the two send the same request and cannot be " <>
       "told apart. The first-visit scenario says whether the application or a cache gave " <>
       "them the same one."}
  end

  # Whether the first response set a cookie, whether the second visitor's
  # response came from a cache, whether the first two visitors hold the
  # same cookies, and whether the application gave the third the same too.
  defp first_visit_verdict({false, true, _same?, _for_everyone?}) do
    {:reused,
     "The first response set no cookie, and a second new visitor was served from the cache."}
  end

  defp first_visit_verdict({false, false, _same?, _for_everyone?}) do
    {:skipped, "The first response a new visitor received set no cookie."}
  end

  defp first_visit_verdict({true, true, true, false}) do
    {:shared_cookie,
     "A second new visitor was served the first visitor's response from the cache, cookie " <>
       "included, where the application gives each visitor a cookie of their own. If it is " <>
       "a session cookie, the two now share a session."}
  end

  defp first_visit_verdict({true, true, true, true}) do
    {:reused,
     "A second new visitor was served from the cache, with a cookie the application gives " <>
       "every visitor alike."}
  end

  defp first_visit_verdict({true, true, false, _for_everyone?}) do
    {:reused,
     "A second new visitor was served from the cache, without the first visitor's cookie."}
  end

  defp first_visit_verdict({true, false, _same?, _for_everyone?}) do
    {:not_reused,
     "A response that sets a cookie was not served from the cache to a second new visitor."}
  end

  defp result(name, verdict, summary, steps) do
    %{
      name: name,
      title: Map.fetch!(@titles, name),
      verdict: verdict,
      summary: summary,
      steps: steps
    }
  end

  # The control is what the application itself serves such a visitor, and
  # the page is what reached them. Where the two differ, something
  # between the application and the visitor served the wrong page,
  # whether or not it says it is a cache.
  defp page_verdict(control, served, labels) do
    facts = {language?(control, labels.wanted), language?(served, labels.wanted)}

    page_outcome(facts, served, labels)
  end

  defp page_outcome({false, _served?}, _served, labels) do
    {:skipped,
     "The application did not serve #{labels.wanted} to such a visitor at a URL no cache had " <>
       "seen: #{labels.hint}."}
  end

  defp page_outcome({true, true}, _served, labels) do
    {:correct, "#{labels.who} was served #{labels.wanted}."}
  end

  defp page_outcome({true, false}, served, labels) do
    {:wrong_language,
     "#{labels.who} was served #{served.language || "a page with no language"} at the page, " <>
       "and #{labels.wanted} at a URL no cache had seen."}
  end

  defp same_visitor_verdict(%Observation{cache_status: :hit}) do
    {:reused, "The third request from one visitor was served from the cache."}
  end

  defp same_visitor_verdict(%Observation{} = observation) do
    unused_verdict(observation)
  end

  defp sharing_verdict(%Observation{cache_status: :hit}, _own) do
    {:shared, "A second visitor, with a cookie of their own, was served from the cache."}
  end

  defp sharing_verdict(_other, %Observation{cache_status: :hit}) do
    {:not_shared,
     "The cache served each visitor only from a copy made for them, so it holds one for " <>
       "every visitor."}
  end

  defp sharing_verdict(other, _own) do
    unused_verdict(other)
  end

  defp header_form_verdict(_short, %Observation{cache_status: :hit}) do
    {:shared, "A request with a longer form of the same header was served from the cache."}
  end

  defp header_form_verdict(%Observation{cache_status: :hit}, _long) do
    {:not_shared,
     "A request with a longer form of the same header was not served from the cache, so " <>
       "each form of the header gets a copy of its own."}
  end

  defp header_form_verdict(short, _long) do
    unused_verdict(short)
  end

  defp unused_verdict(%Observation{cache_status: :uncacheable}) do
    {:not_cached, "The cache reports that it will not store this response."}
  end

  defp unused_verdict(%Observation{cache_control: directives}) do
    if Enum.any?(directives, &(&1 in @unshared_directives)) do
      {:not_cached,
       "The response keeps itself out of a shared cache with cache-control: " <>
         Enum.join(directives, ", ") <> "."}
    else
      {:not_reused, "No header shows a repeated request served from a cache."}
    end
  end

  # A page matches a wanted locale when it is that locale or a more
  # specific one: `fr-ca` is a match for `fr`, and `fr` is not for `fr-CA`.
  defp language?(%Observation{language: nil}, _wanted) do
    false
  end

  defp language?(%Observation{language: served}, wanted) do
    wanted = String.downcase(wanted)

    served == wanted or String.starts_with?(served, wanted <> "-")
  end
end
