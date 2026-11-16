defmodule LocalizeCacheProbe.HeadersTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Headers

  doctest LocalizeCacheProbe.Headers

  @headers [
    {"Vary", "accept-language"},
    {"content-type", "text/html"},
    {"vary", " Accept-Encoding , ,COOKIE"},
    {"vary", "accept-language"}
  ]

  test "first/2 returns the first line, whatever the case of its name" do
    assert Headers.first(@headers, "vary") == "accept-language"
    assert Headers.first(@headers, "content-type") == "text/html"
    assert Headers.first(@headers, "age") == nil
  end

  test "all/2 keeps every line in order" do
    assert Headers.all(@headers, "vary") ==
             ["accept-language", " Accept-Encoding , ,COOKIE", "accept-language"]

    assert Headers.all(@headers, "age") == []
  end

  test "members/2 combines the lines, trimmed, lower case and unique" do
    assert Headers.members(@headers, "vary") == ["accept-language", "accept-encoding", "cookie"]
    assert Headers.members(@headers, "age") == []
    assert Headers.members([{"vary", ""}, {"vary", " , "}], "vary") == []
  end

  test "entries that are not a pair of strings are ignored" do
    headers = [nil, {:vary, "a"}, {"vary", nil}, "vary", {"vary", "b", "c"}, {"vary", "kept"}]

    assert Headers.first(headers, "vary") == "kept"
    assert Headers.all(headers, "vary") == ["kept"]
    assert Headers.members(headers, "vary") == ["kept"]
  end
end
