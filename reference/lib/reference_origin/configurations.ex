defmodule ReferenceOrigin.Default do
  @moduledoc """
  `Localize.Plug.PutLocale` with its default options, followed by
  `Localize.Plug.PutSession`.

  The sources are the route, the path, the query, the session and
  `accept-language`, and the plug sends `vary` for the request headers
  it reads.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
end

defmodule ReferenceOrigin.NoSession do
  @moduledoc """
  `Localize.Plug.PutLocale` with the session left out of `:from`, and no
  `Localize.Plug.PutSession`.

  The response varies on `accept-language` alone, and a locale a visitor
  chose is not remembered.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale, from: [:route, :path, :query, :accept_language]
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
end

defmodule ReferenceOrigin.VaryOff do
  @moduledoc """
  The default sources with `vary: false`, and nothing else declaring how
  the response varies.

  This is the configuration the documentation warns about: the session
  and `accept-language` still choose the locale, and a cache in front is
  told nothing.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale, vary: false
  plug Localize.Plug.PutSession
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
end

defmodule ReferenceOrigin.TwoVary do
  @moduledoc """
  The default configuration behind a plug that has already set a `vary`
  line, so the response carries two.

  A cache has to combine the lines. One that reads only the first sees
  `accept-encoding` and misses the fields `Localize.Plug.PutLocale`
  added.

  """

  use Plug.Builder

  plug :vary_on_encoding
  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  @doc false
  def vary_on_encoding(conn, _options) do
    Plug.Conn.put_resp_header(conn, "vary", "accept-encoding")
  end
end

defmodule ReferenceOrigin.Visitor do
  @moduledoc """
  The default configuration, with a value of the visitor's own in the
  session.

  A session that holds only the locale is a cookie that every visitor
  with that locale shares, byte for byte. Most applications keep more
  than that: a CSRF token, a user id, a cart. This configuration puts a
  random token in the session on a first visit, so that each visitor's
  cookie differs, as it does in such an application.

  """

  use Plug.Builder

  @token_bytes 12

  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession
  plug :put_visitor_token
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  @doc false
  def put_visitor_token(conn, _options) do
    if is_nil(Plug.Conn.get_session(conn, "visitor")) do
      Plug.Conn.put_session(conn, "visitor", token())
    else
      conn
    end
  end

  defp token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end

defmodule ReferenceOrigin.PrivateSession do
  @moduledoc """
  The default configuration, with `cache-control: private` on any
  response that writes the session.

  A response that sets the session cookie is made for one visitor. Sent
  as `public`, a cache may store it and answer the next visitor in the
  application's place, so that visitor's first visit or choice of locale
  never reaches the application. This configuration marks such a
  response `private` and leaves every other response `public`.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession
  plug :private_when_session_written
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  # `Localize.Plug.PutSession.stored?/1` says whether the plug wrote the
  # locale to the session for this request, which is when the response
  # sets the session cookie.
  @doc false
  def private_when_session_written(conn, _options) do
    if Localize.Plug.PutSession.stored?(conn) do
      Plug.Conn.assign(conn, :cache_control, "private")
    else
      conn
    end
  end
end

defmodule ReferenceOrigin.Chosen do
  @moduledoc """
  The default sources, storing the locale only when the visitor chose it.

  `Localize.Plug.PutSession` stores every locale by default, a guess
  from `accept-language` included, so every first visit sets a cookie.
  Its `:from` option names the sources whose locale is stored. Here that
  is the URL and the query, so a visitor who never chose is given no
  cookie.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession, from: [:route, :path, :query, :body]
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
end

defmodule ReferenceOrigin.ChosenPrivate do
  @moduledoc """
  `ReferenceOrigin.Chosen`, with `cache-control: private` on any response
  that writes the session.

  The two changes together: no cookie for a visitor who never chose, and
  the response that stores a choice kept out of shared caches.

  The response is made private when the session is written, and not
  whenever the locale came from a stored source. A locale in the path is
  on every request for that page, and making all of those private kept
  the page out of every cache when it was tried.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug Localize.Plug.PutSession, from: [:route, :path, :query, :body]
  plug :private_when_session_written
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  defdelegate private_when_session_written(conn, options),
    to: ReferenceOrigin.PrivateSession
end

defmodule ReferenceOrigin.Normalised do
  @moduledoc """
  A cache inside the application that keys on a normalised
  `accept-language`, as described by the author of `plug_http_cache`.

  The locale is resolved first, from the URL, the session or the header,
  and stored in the session. The request's `accept-language` is then
  rewritten to the locale that was resolved, so a visitor whose session
  holds `de` and whose browser asks for `fr` reaches the cache asking
  for `de`. `PlugHTTPCache` comes next, inside this pipeline and not in
  front of the router, and the response declares `vary: accept-language`
  itself, so `Localize.Plug.PutLocale` is told to send none.

  The session plugs run before the cache on every request, a hit
  included, so the session cookie is written whether or not the page
  comes from the cache.

  The rewrite happens inside the application. A cache in front of it
  sees the request as the browser sent it, and is told only that the
  response varies on `accept-language`.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale, vary: false
  plug Localize.Plug.PutSession
  plug :normalise_accept_language
  plug PlugHTTPCache, %{store: :http_cache_store_memory}
  plug :vary_on_accept_language
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  @doc false
  def normalise_accept_language(conn, _options) do
    case Localize.Plug.PutLocale.get_locale(conn) do
      %Localize.LanguageTag{cldr_locale_id: locale_id} when not is_nil(locale_id) ->
        Plug.Conn.put_req_header(conn, "accept-language", to_string(locale_id))

      _other ->
        conn
    end
  end

  @doc false
  def vary_on_accept_language(conn, _options) do
    Plug.Conn.prepend_resp_headers(conn, [{"vary", "accept-language"}])
  end
end
