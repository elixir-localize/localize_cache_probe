defmodule ReferenceOrigin.Cached do
  @moduledoc """
  The reference origin with `PlugHTTPCache` in front of it.

  This is a cache inside the application: the plug runs before the
  router, stores responses in memory, and answers from the store when it
  may. It is served on a port of its own, so the probe can be pointed at
  the same pages with and without it.

  The cache is `http_cache` with the plug's defaults, which make it a
  shared cache. Nothing is tuned.

  """

  use Plug.Builder

  plug(PlugHTTPCache, %{store: :http_cache_store_memory})
  plug(ReferenceOrigin.Router)
end
