defmodule LocalizeCacheProbe.TestApplication do
  @moduledoc false

  # A model of an application that resolves the locale the way
  # `Localize.Plug.PutLocale` does by default and stores it the way
  # `Localize.Plug.PutSession` does, with a model cache in front of it.
  #
  # The locale comes from the first segment of the path, then the
  # `locale` query parameter, then the session cookie, then
  # `accept-language`, then `en`. The response names in `vary` the
  # request headers that were read, and sets the session cookie when the
  # locale it holds changes.
  #
  # The cache is one of:
  #
  # * `:none` — every request reaches the application.
  #
  # * `:honours_vary` — reuses a response only for a request that sends
  #   the same value for every header its `vary` named, and stores no
  #   response that sets a cookie.
  #
  # * `:ignores_vary` — keyed on the path alone, and stores everything,
  #   `set-cookie` included.

  alias LocalizeCacheProbe.TestOrigin

  @locales ["fr", "de", "en", "fr-FR", "fr-CH"]
  @session ~r/(?:^|;\s*)s=([A-Za-z-]+)\.(\d+)/

  def start(cache) when cache in [:none, :honours_vary, :ignores_vary] do
    TestOrigin.start(%{cache: cache, stored: %{}, sessions: 0}, &handle/2)
  end

  # The cache holds, for each request target, the responses stored for
  # it. Each is kept with the request headers its `vary` named and the
  # values they had, and is reused for a request that sends the same.
  defp handle(text, state) do
    request = parse(text)
    entries = Map.get(state.stored, request.target, [])

    case Enum.find(entries, &selected?(&1, request)) do
      {_selecting, {status, headers, body}} ->
        {TestOrigin.response(status, [{"Age", "1"} | headers], body), state}

      nil ->
        {{status, headers, body} = response, vary, state} = render(request, state)

        {TestOrigin.response(status, headers, body), store(state, request, vary, response)}
    end
  end

  defp selected?({selecting, _response}, request) do
    Enum.all?(selecting, fn {field, value} -> request_header(request, field) == value end)
  end

  defp request_header(request, "cookie") do
    request.cookie
  end

  defp request_header(request, "accept-language") do
    request.accept_language
  end

  defp store(%{cache: :none} = state, _request, _vary, _response) do
    state
  end

  defp store(%{cache: :honours_vary} = state, request, vary, response) do
    {_status, headers, _body} = response

    if List.keymember?(headers, "Set-Cookie", 0) do
      state
    else
      selecting = Map.new(vary, &{&1, request_header(request, &1)})
      keep(state, request.target, {selecting, response})
    end
  end

  defp store(%{cache: :ignores_vary} = state, request, _vary, response) do
    keep(state, request.target, {%{}, response})
  end

  defp keep(state, target, entry) do
    entries = Map.get(state.stored, target, [])

    %{state | stored: Map.put(state.stored, target, [entry | entries])}
  end

  defp render(request, state) do
    {locale, vary} = locale(request)
    {cookie_headers, state} = session(request, locale, state)

    headers =
      [{"Content-Language", locale}, {"Cache-Control", "public, max-age=60"}] ++
        vary_headers(vary) ++ cookie_headers

    {{200, headers, "<html lang=\"#{locale}\">"}, vary, state}
  end

  # The locale, and the request headers that were read to find it.
  defp locale(request) do
    stored = stored_locale(request.cookie)
    asked = supported(first_tag(request.accept_language))

    cond do
      not is_nil(request.path_locale) -> {request.path_locale, []}
      not is_nil(request.query_locale) -> {request.query_locale, []}
      not is_nil(stored) -> {stored, ["cookie"]}
      not is_nil(asked) -> {asked, ["cookie", "accept-language"]}
      true -> {"en", ["cookie", "accept-language"]}
    end
  end

  # Every response has a `vary` line for the encoding, as a server that
  # compresses adds one, so the fields the locale was read from arrive
  # on a second line.
  defp vary_headers([]) do
    [{"Vary", "accept-encoding"}]
  end

  defp vary_headers([_ | _] = fields) do
    [{"Vary", "accept-encoding"}, {"Vary", Enum.join(fields, ", ")}]
  end

  defp session(request, locale, state) do
    if stored_locale(request.cookie) == locale do
      {[], state}
    else
      sessions = state.sessions + 1

      {[{"Set-Cookie", "s=#{locale}.#{sessions}; path=/; HttpOnly"}],
       %{state | sessions: sessions}}
    end
  end

  defp stored_locale(nil) do
    nil
  end

  defp stored_locale(cookie) do
    case Regex.run(@session, cookie, capture: :all_but_first) do
      [locale, _id] -> locale
      nil -> nil
    end
  end

  defp parse(text) do
    [request_line | header_lines] = String.split(text, "\r\n")
    [_method, target, _version] = String.split(request_line, " ")
    uri = URI.parse(target)

    %{
      target: target,
      path_locale: path_locale(uri.path),
      query_locale: supported(URI.decode_query(uri.query || "")["locale"]),
      cookie: header(header_lines, "cookie"),
      accept_language: header(header_lines, "accept-language")
    }
  end

  defp path_locale(path) do
    case String.split(path, "/", trim: true) do
      [segment | _rest] -> supported(segment)
      [] -> nil
    end
  end

  defp supported(locale) do
    if locale in @locales do
      locale
    else
      nil
    end
  end

  defp first_tag(nil) do
    nil
  end

  defp first_tag(accept_language) do
    accept_language
    |> String.split([",", ";"])
    |> List.first()
    |> String.trim()
  end

  defp header(lines, name) do
    Enum.find_value(lines, &header_value(&1, name))
  end

  defp header_value(line, name) do
    case String.split(line, ":", parts: 2) do
      [header_name, value] -> matching(String.downcase(header_name), name, String.trim(value))
      [_other] -> nil
    end
  end

  defp matching(name, name, value) do
    value
  end

  defp matching(_header_name, _name, _value) do
    nil
  end
end
