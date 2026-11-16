defmodule ReferenceOrigin.Router do
  @moduledoc """
  Routes each configuration of `Localize.Plug.PutLocale` to a path of
  its own.

  | Path | Configuration |
  |---|---|
  | `/default/page` | `ReferenceOrigin.Default` |
  | `/no-session/page` | `ReferenceOrigin.NoSession` |
  | `/vary-off/page` | `ReferenceOrigin.VaryOff` |
  | `/two-vary/page` | `ReferenceOrigin.TwoVary` |
  | `/visitor/page` | `ReferenceOrigin.Visitor` |

  Each also answers with a locale in the path, such as
  `/default/de/page`, which `Localize.Plug.PutLocale` reads through its
  `:path` source.

  The session is a signed cookie. Its key is fixed in this file because
  the origin is a demonstration that holds nothing worth protecting; it
  must not be copied into an application.

  """

  use Plug.Router

  # Fixed and public on purpose: see the moduledoc.
  @secret_key_base String.duplicate("reference-origin-not-a-secret", 3)

  plug :put_secret_key_base

  plug Plug.Session,
    store: :cookie,
    key: "_reference_origin",
    signing_salt: "reference"

  plug :fetch_session
  plug :fetch_query_params
  plug :match
  plug :dispatch

  get "/default/page", to: ReferenceOrigin.Default
  get "/default/:locale/page", to: ReferenceOrigin.Default

  get "/no-session/page", to: ReferenceOrigin.NoSession
  get "/no-session/:locale/page", to: ReferenceOrigin.NoSession

  get "/vary-off/page", to: ReferenceOrigin.VaryOff
  get "/vary-off/:locale/page", to: ReferenceOrigin.VaryOff

  get "/two-vary/page", to: ReferenceOrigin.TwoVary
  get "/two-vary/:locale/page", to: ReferenceOrigin.TwoVary

  get "/visitor/page", to: ReferenceOrigin.Visitor
  get "/visitor/:locale/page", to: ReferenceOrigin.Visitor

  match _ do
    send_resp(conn, 404, "not found")
  end

  @doc false
  def put_secret_key_base(conn, _options) do
    %{conn | secret_key_base: @secret_key_base}
  end
end
