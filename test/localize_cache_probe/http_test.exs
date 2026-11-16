defmodule LocalizeCacheProbe.HTTPTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Headers
  alias LocalizeCacheProbe.HTTP
  alias LocalizeCacheProbe.TestOrigin

  doctest LocalizeCacheProbe.HTTP

  test "returns the status, the body and every header line" do
    response =
      TestOrigin.response(
        200,
        [
          {"Content-Language", "fr"},
          {"Vary", "accept-language"},
          {"Vary", "Accept-Encoding"},
          {"Set-Cookie", "a=1; Path=/; Expires=Wed, 18 Nov 2026 00:00:00 GMT"},
          {"Set-Cookie", "b=2; Path=/"}
        ],
        "<html lang=\"fr\">bonjour</html>"
      )

    url = TestOrigin.start([response])

    assert {:ok, %{status: 200, headers: headers, body: body}} = HTTP.get(url <> "/page")
    assert body == "<html lang=\"fr\">bonjour</html>"
    assert Headers.all(headers, "vary") == ["accept-language", "Accept-Encoding"]

    assert Headers.all(headers, "set-cookie") ==
             ["a=1; Path=/; Expires=Wed, 18 Nov 2026 00:00:00 GMT", "b=2; Path=/"]
  end

  test "sends the path, the query and the caller's headers" do
    url = TestOrigin.start([TestOrigin.response(200, [])])

    assert {:ok, %{status: 200}} =
             HTTP.get(url <> "/pricing?locale=de", [
               {"accept-language", "de-CH"},
               {"cookie", "a=1"}
             ])

    assert_receive {:request, request}
    assert request =~ "GET /pricing?locale=de HTTP/1.1\r\n"
    assert request =~ ~r/accept-language: de-CH\r\n/i
    assert request =~ ~r/cookie: a=1\r\n/i
    assert request =~ ~r/user-agent: localize-cache-probe/i
  end

  test "requests / when the URL has no path" do
    url = TestOrigin.start([TestOrigin.response(200, [])])

    assert {:ok, %{status: 200}} = HTTP.get(url)
    assert_receive {:request, "GET / HTTP/1.1\r\n" <> _rest}
  end

  test "does not follow a redirect" do
    url = TestOrigin.start([TestOrigin.response(302, [{"Location", "/fr/page"}])])

    assert {:ok, %{status: 302, headers: headers}} = HTTP.get(url <> "/page")
    assert Headers.first(headers, "location") == "/fr/page"
  end

  test "returns an error for a URL it cannot request" do
    for url <- ["", "example.com/page", "ftp://example.com/", "http://", "mailto:a@example.com"] do
      assert {:error, %ArgumentError{}} = HTTP.get(url)
    end
  end

  test "returns an error when nothing is listening" do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(listen)
    :ok = :gen_tcp.close(listen)

    assert {:error, %Mint.TransportError{}} = HTTP.get("http://127.0.0.1:#{port}/")
  end
end
