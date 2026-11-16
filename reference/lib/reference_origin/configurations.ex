defmodule ReferenceOrigin.Default do
  @moduledoc """
  `Localize.Plug.PutLocale` with its default options, followed by
  `Localize.Plug.PutSession`.

  The sources are the route, the path, the query, the session and
  `accept-language`, and the plug sends `vary` for the request headers
  it reads.

  """

  use Plug.Builder

  plug(Localize.Plug.PutLocale)
  plug(Localize.Plug.PutSession)
  plug(:render)

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

  plug(Localize.Plug.PutLocale, from: [:route, :path, :query, :accept_language])
  plug(:render)

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

  plug(Localize.Plug.PutLocale, vary: false)
  plug(Localize.Plug.PutSession)
  plug(:render)

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

  plug(:vary_on_encoding)
  plug(Localize.Plug.PutLocale)
  plug(Localize.Plug.PutSession)
  plug(:render)

  defdelegate render(conn, options), to: ReferenceOrigin.Page

  @doc false
  def vary_on_encoding(conn, _options) do
    Plug.Conn.put_resp_header(conn, "vary", "accept-encoding")
  end
end
