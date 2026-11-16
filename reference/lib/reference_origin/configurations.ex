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

  # `Plug.Conn.put_session/3` records that the session is to be written
  # under this key, which `Plug.Session` reads when the response is
  # sent. Plug has no public function that says the same.
  @doc false
  def private_when_session_written(conn, _options) do
    if conn.private[:plug_session_info] == :write do
      Plug.Conn.assign(conn, :cache_control, "private")
    else
      conn
    end
  end
end

defmodule ReferenceOrigin.Chosen do
  @moduledoc """
  The default sources, storing the locale only when the visitor chose it.

  `Localize.Plug.PutSession` stores whatever locale was resolved, a
  guess from `accept-language` included, so every first visit sets a
  cookie. This configuration stores the locale only when the request
  named one, in its query or its path, and so sets no cookie for a
  visitor who never chose. It is a sketch of a change that has been
  proposed for `localize_web`, made here with a plug of the origin's own.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug :put_session_when_chosen
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
  defdelegate put_session_when_chosen(conn, options), to: ReferenceOrigin.ChosenSession
end

defmodule ReferenceOrigin.ChosenPrivate do
  @moduledoc """
  `ReferenceOrigin.Chosen`, with `cache-control: private` on any response
  that writes the session.

  The two changes together: no cookie for a visitor who never chose, and
  the response that stores a choice kept out of shared caches.

  """

  use Plug.Builder

  plug Localize.Plug.PutLocale
  plug :put_session_when_chosen
  plug :private_when_session_written
  plug :render

  defdelegate render(conn, options), to: ReferenceOrigin.Page
  defdelegate put_session_when_chosen(conn, options), to: ReferenceOrigin.ChosenSession

  defdelegate private_when_session_written(conn, options),
    to: ReferenceOrigin.PrivateSession
end

defmodule ReferenceOrigin.ChosenSession do
  @moduledoc """
  Stores the resolved locale in the session only when the request named
  a locale.

  `Localize.Plug.PutLocale` does not say which source decided, so this
  takes a `locale` parameter in the query or the path as the sign of a
  choice. A request that names a locale the application does not support
  is treated as a choice too, which a real implementation would not do.

  """

  @param "locale"

  @doc """
  Calls `Localize.Plug.PutSession` when the request named a locale.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0` that `Localize.Plug.PutLocale` has
    already been through, with its query parameters fetched.

  * `options` is ignored.

  ### Returns

  * The `conn`, with the locale put in the session when the query or the
    path held a `locale` parameter.

  """
  @spec put_session_when_chosen(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def put_session_when_chosen(conn, _options) do
    if chosen?(conn) do
      Localize.Plug.PutSession.call(conn, Localize.Plug.PutSession.init([]))
    else
      conn
    end
  end

  defp chosen?(conn) do
    Map.has_key?(conn.query_params, @param) or Map.has_key?(conn.path_params, @param)
  end
end
