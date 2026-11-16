defmodule ReferenceOrigin.Page do
  @moduledoc """
  Renders the one page the reference origin serves.

  `render/2` is used as the last plug of each configuration. It names
  the locale that `Localize.Plug.PutLocale` resolved in the
  `content-language` header and in the `lang` of the `html` element, and
  makes the response storable by a shared cache with
  `cache-control: public`. Without that, Plug's default keeps every
  response private and there is nothing for a cache to get wrong.

  """

  import Plug.Conn

  @cache_control "public, max-age=60"

  @doc """
  Sends the page for the locale resolved for the request.

  ### Arguments

  * `conn` is a `t:Plug.Conn.t/0` that `Localize.Plug.PutLocale` has
    already been through.

  * `options` is ignored.

  ### Returns

  * The `conn` with the response sent.

  """
  @spec render(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def render(conn, _options) do
    locale = locale(Localize.Plug.PutLocale.get_locale(conn))

    conn
    |> put_resp_header("cache-control", @cache_control)
    |> put_resp_header("content-language", locale)
    |> put_resp_content_type("text/html")
    |> send_resp(200, body(locale, conn.request_path))
  end

  defp locale(%Localize.LanguageTag{cldr_locale_id: locale_id}) when not is_nil(locale_id) do
    to_string(locale_id)
  end

  defp locale(_other) do
    "und"
  end

  defp body(locale, path) do
    """
    <!DOCTYPE html>
    <html lang="#{locale}">
      <head><title>Reference origin</title></head>
      <body><p>#{path} in #{locale}</p></body>
    </html>
    """
  end
end
