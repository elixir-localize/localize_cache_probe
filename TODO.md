# TODO

Work planned for the Localize cache probe. It grew out of [localize_web issue 28](https://github.com/elixir-localize/localize_web/issues/28), which is where the scenarios come from.

## Open

* [ ] **Run it through a hosted cache** — Cloudflare, Fastly, CloudFront, Google Cloud CDN, Azure Front Door and Akamai are known only from their documentation. Each needs the origin reachable from the internet and an account, which are Kip's to set up.

* [ ] **Start each scenario from a clean cache** — an earlier scenario leaves pages in the cache that change what a later one finds. Behind Varnish and nginx with `vary: false`, the first scenario passes only because nothing is stored yet. A query parameter of its own for each scenario would separate them.

* [ ] **Tests for the reference origin** — it has none; its behaviour is checked only by running the probe against it.

* [ ] **Say when the page redirects** — a redirect is not followed, so a page that redirects gives every scenario an inconclusive verdict with no language. Name the `location` in the report and suggest probing that URL.

* [ ] **Vary notes for Fastly, Varnish, nginx and `http_cache`** — read each project's documentation and add a note with its source, as the other vendors have.

* [ ] **CI workflow** — the standard matrix does not apply to an application on one toolchain; add a single lint and test row.

* [ ] **Limit the body the client reads** — `LocalizeCacheProbe.HTTP.get/2` reads a whole response into memory; stop at a few megabytes.

## Done

* [x] **Go private with `PutSession.stored?/1`** — `/private-session` and `/chosen-private` ask `localize_web` whether the session was written, in place of reading a Plug-internal key, with the same verdicts behind all three caches. 2026-11-17.

* [x] **`/chosen` on the real option** — the reference origin uses `Localize.Plug.PutSession, from: [...]` from `localize_web` 1.4.0 in place of its own sketch, with the same verdicts; `/chosen-private` goes private on a session write, after going private by source kept the URL-locale page out of every cache. 2026-11-17.

* [x] **Storing only a chosen locale, tried** — `/chosen/page` and `/chosen-private/page` in the reference origin; two new visitors then share a copy behind every cache, at the cost of a copy for each form of `accept-language`. The first-visit scenario now reports that reuse when no cookie is set. 2026-11-17.

* [x] **`cache-control: private` when the session is written** — `/private-session/page` in the reference origin; behind `plug_http_cache` the second visitor's choice is then stored and every verdict matches Varnish and nginx. 2026-11-17.

* [x] **A scenario for a second visitor's choice** — `:second_choice` has two visitors choose through one URL and checks each with a control request; the verdict `choice lost` exits with status 1. The stored-locale check now uses a choose URL of its own, so an earlier scenario cannot leave it in the cache. 2026-11-17.

* [x] **A scenario for several `vary` lines** — `:vary_lines` repeats the checks on `accept-language` and the cookie and reports each against the line that named it; `Observation` keeps the members of each line apart. 2026-11-17.

* [x] **Two visitors with the same cookie** — the two-visitor scenario is skipped when the visitors hold the same cookies or none, the first-visit scenario asks a third visitor whether the application gives everyone the same cookie before it calls one shared, and `/visitor/page` in the reference origin gives each visitor a cookie of their own. 2026-11-17.

* [x] **Three caches in front of the reference origin** — `plug_http_cache` on port 4011, and Varnish and nginx in Docker; the probe's verdicts for all four configurations are in the README. 2026-11-17.

* [x] **A control request for the language verdicts** — the same kind of visitor asks at a URL no cache has seen, so a wrong language no longer needs a cache header and an application that stores no choice is skipped, not failed. 2026-11-17.

* [x] **Reference origin** — `reference/` serves four `Localize.Plug.PutLocale` configurations from the sibling `localize_web` checkout, each at a path of its own, and the probe's eight scenarios run against it with no cache in front. 2026-11-17.

* [x] **Six more scenarios** — different locales, two visitors with one locale, two forms of one header, two regions, a locale in the URL and a first visit that sets a cookie, with `--regions` and `--localized-url`; a shared cookie also exits with status 1. 2026-11-17.

* [x] **`mix cache.probe URL`** — runs every scenario against a page and prints a report, with `--locales`, `--param` and `--choose-url`; exits with status 1 on a wrong language served from a cache. 2026-11-17.

* [x] **The first two scenarios** — `LocalizeCacheProbe.Scenario` plays a visitor with a stored locale after another visitor's page is cached, and one visitor three times, and `LocalizeCacheProbe.Report` tabulates them. 2026-11-17.

* [x] **HTTP fetch and a visitor with a cookie jar** — `LocalizeCacheProbe.HTTP.get/2` makes one `GET` with Mint and keeps every header line, and `LocalizeCacheProbe.Visitor.visit/2` requests a URL as a visitor and keeps the cookies it is sent. 2026-11-17.

* [x] **Observation of one response** — `LocalizeCacheProbe.Observation.new/3` records the language served, the `vary` lines, `cache-control`, `set-cookie` and the cache status. 2026-11-17.

* [x] **Cache recognition** — `LocalizeCacheProbe.Cache` names the cache from response headers, reads hit or miss, and records what Akamai, Cloudflare, CloudFront, Google Cloud CDN and Azure Front Door document about `vary`. 2026-11-17.
