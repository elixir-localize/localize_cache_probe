# Localize cache probe

A client that shows how the cache in front of an application treats the `vary` header that [`localize_web`](https://hex.pm/packages/localize_web) sends. It plays two visitors against a page of the application, and reports which language each was served and whether the response came from a cache.

It grew out of [localize_web issue 28](https://github.com/elixir-localize/localize_web/issues/28). The probe is a demonstration and is not published to Hex.

## Status

The probe runs eight scenarios against a page and prints a report. It has been run against the reference origin in `reference/` behind `plug_http_cache`, Varnish and nginx, and the results are below. It has not been run against a hosted cache or against an application of any size.

## Quick start

Point the task at a page of an application you operate, one whose URL holds no locale, and name two locales the application supports.

```bash
mix cache.probe https://example.com/pricing --locales fr,de
```

The first locale is the one a browser asks for with `accept-language`. The second is the one a visitor chooses, which the probe does by requesting the page with `?locale=de` and keeping the session cookie the application sends back. `--param` changes the parameter name, and `--choose-url` takes a URL template holding `{locale}` for an application that chooses a locale another way.

Two scenarios need more than a page and two locales, and are skipped without their option:

```bash
mix cache.probe https://example.com/pricing --locales fr,de --regions fr-FR,fr-CH --localized-url 'https://example.com/{locale}/pricing'
```

`--regions` names two regional locales of one language that the application serves differently. `--localized-url` is a template for the same page with the locale in its URL.

The probe sends about 30 `GET` requests, and the cache in front of the application may store what comes back.

The report names the cache, gives what its vendor documents about `vary` where that has been read, and lists each scenario with a verdict and the requests made. This one is the reference origin's `vary: false` configuration behind Varnish:

```text
2. A visitor with a stored locale, after another visitor's page is cached
   Verdict: WRONG LANGUAGE
   The visitor who chose de was served fr at the page, and de at a URL no cache had seen.

   visitor  asks for  request                                 status  language  vary             cache
   A        fr        /vary-off/page                          200     fr        accept-encoding  miss
   A        fr        /vary-off/page                          200     fr        accept-encoding  miss
   B        fr        /vary-off/page?locale=de                200     de        accept-encoding  miss
   B        fr        /vary-off/page?_probe=1794861593673148  200     de        accept-encoding  miss
   B        fr        /vary-off/page                          200     fr        accept-encoding  hit
```

The task exits with status 1 when a visitor is served the wrong language from a cache, or the cookie stored with another visitor's response, so it can gate a deployment.

## Scenarios

| Scenario | What it shows |
|---|---|
| Two visitors whose browsers ask for different locales | Whether the cache takes account of `accept-language`. |
| A visitor with a stored locale, after another visitor's page is cached | Whether the cache takes account of the cookie. |
| One visitor, three requests | What a developer sees checking a cache in one browser. |
| Two visitors who ask for the same locale, each with a cookie of their own | Whether the cache serves both from one copy or keeps one for each. |
| One visitor, two forms of the same `accept-language` | Whether each form of the header gets a copy of its own. |
| Two visitors whose browsers ask for different regions of one language | Whether the cache folds a region into its language. Needs `--regions`. |
| Two visitors at the page with a locale in its URL | Whether a page that no request header decides is shared. Needs `--localized-url`. |
| Two new visitors, when the first response sets a cookie | Whether the cache stores that response, and hands the cookie to someone else. |

The three scenarios that judge the language make a control request: the same kind of visitor asks for the page at a URL with a `_probe` parameter no request has carried before, so no cache has it stored and the application answers. Where the application serves that visitor one language and the page reaches them in another, the verdict is a wrong language, whether or not anything says it is a cache. Where the application itself does not serve the expected language, the scenario is skipped: an application with no session does not store a choice, and there is nothing for a cache to get wrong.

The control assumes the cache keys on the query string. Behind one configured to ignore it, the control is served from the cache too, and those scenarios are skipped.

Each scenario starts from whatever the cache already holds, so an earlier scenario can change what a later one finds stored.

## Reference origin

`reference/` is a small Plug application to point the probe at when there is no deployed application to hand. It runs `Localize.Plug.PutLocale` from the sibling `localize_web` checkout, so it shows the code under discussion, released or not. It serves `en`, `fr`, `de`, `fr-CA` and `fr-CH`, and makes every response storable with `cache-control: public`.

| Path | Configuration |
|---|---|
| `/default/page` | `PutLocale` with its default options, then `PutSession`. |
| `/no-session/page` | The session left out of `:from`, and no `PutSession`. |
| `/vary-off/page` | The default sources with `vary: false`. |
| `/two-vary/page` | The default configuration behind a plug that sets a `vary` line first. |

Each also answers with a locale in the path, such as `/default/de/page`.

Fetch the locale data once, then start it on port 4010:

```bash
cd reference && mix deps.get && mix localize.download_locales
```

```bash
cd reference && mix run --no-halt
```

Then, from the repository root:

```bash
mix cache.probe http://127.0.0.1:4010/default/page --locales fr,de --regions fr-CA,fr-CH --localized-url 'http://127.0.0.1:4010/default/{locale}/page'
```

That port has no cache in front, so it shows what the application itself sends. Three caches are available in front of the same pages:

| Port | Cache | How it is set up |
|---|---|---|
| 4010 | none | The origin. |
| 4011 | `plug_http_cache` | Inside the application, in front of the router, with the plug's defaults and the memory store. |
| 4020 | Varnish | In Docker. One change from the shipped rules: a request that carries a cookie is looked up, where Varnish would pass it to the origin. |
| 4030 | nginx | In Docker, `proxy_cache` with its defaults. |

The first two start with the origin. For the other two, with Docker running:

```bash
docker compose -f reference/caches/compose.yaml up -d
```

The origin's session holds nothing but the locale, so its signed cookie is the same for every visitor with the same locale. An application whose session also holds something of the visitor's own, such as a CSRF token, sends each visitor a different cookie.

### Results

Run on 2026-11-17 with `localize_web` 1.4.0 before its release, Bandit 1.14.1, `plug_http_cache` 1.0.0 on `http_cache` 1.0.0, Varnish 7.6 and nginx 1.27.5. Each cell is the verdict behind `plug_http_cache`, Varnish and nginx in that order, or one verdict where all three agree.

| Scenario | `/default` | `/no-session` | `/vary-off` | `/two-vary` |
|---|---|---|---|---|
| Different locales | correct | correct | wrong, correct, correct | correct |
| Stored locale | correct | skipped | wrong language | correct |
| One visitor | reused | reused | reused | reused |
| Two visitors | shared | shared | shared | shared |
| Two header forms | not shared, shared, shared | not shared | shared | not shared, shared, shared |
| Two regions | correct | correct | wrong language | correct |
| Locale in the URL | shared | shared | shared | shared |
| First visit | skipped, not reused, not reused | skipped | skipped | skipped, not reused, not reused |

What the table shows:

* **The default configuration is correct behind all three caches.** No visitor was served another's language.

* **`vary: false` with the session still read serves the wrong language behind all three.** This is the configuration the `localize_web` documentation warns about.

* **All three caches combine two `vary` lines.** Bandit adds `vary: accept-encoding` on a line of its own, so every response from the origin carries two, and `/default` and `/two-vary` give the same verdicts.

* **Varnish and nginx never store a response that sets a cookie; `http_cache` stores it and leaves the cookie out when it serves it.** That is why `vary: false` fails on a first visit only behind `plug_http_cache`, and why a new visitor served from its cache is given no session cookie.

* **"Two visitors: shared" is the origin's identical cookie, not a cache ignoring `vary: cookie`.** Both visitors hold the same signed cookie, so they send the same request.

* **With no session, each form of `accept-language` gets a copy of its own.** That is the fragmentation a cache avoids by normalising the header.

## Recognising the cache

`LocalizeCacheProbe.Cache` names the cache in front of an application, reads whether a response was a hit, and returns what the vendor documents about `vary`.

```elixir
iex> headers = [{"x-cache", "Miss from cloudfront"}, {"x-amz-cf-pop", "SYD62-P1"}]
iex> LocalizeCacheProbe.Cache.vendor(headers)
:cloudfront
iex> LocalizeCacheProbe.Cache.status(headers)
:miss
iex> {:ok, note} = LocalizeCacheProbe.Cache.vary_note(:cloudfront)
iex> note.source
"https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html"
```

## What each vendor documents

Each line is taken from the vendor's own documentation in November 2026. None has been tested here; testing them is what the probe is for.

| Cache | Documented treatment of `vary` |
|---|---|
| Akamai | Stores nothing with a `vary` other than `accept-encoding` on compressed content. |
| Cloudflare | Ignores `vary` until a Cache Rule turns it on. |
| Amazon CloudFront | Keys on the headers its cache policy names, and none by default. |
| Google Cloud CDN | Stores nothing whose `vary` names `cookie` or `accept-language`. |
| Azure Front Door | Does not document `vary`, and does not forward `accept-language` when caching. |

Fastly, Varnish, nginx and `http_cache` are recognised, and their documentation has not been read yet.

## Supported Elixir and OTP versions

Elixir **1.20** on OTP **29**. The probe is an application and runs on one toolchain.

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
