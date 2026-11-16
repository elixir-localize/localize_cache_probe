defmodule LocalizeCacheProbe.ObservationTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Observation

  doctest LocalizeCacheProbe.Observation

  @page ~s(<!DOCTYPE html>\n<html class="no-js" lang="de-CH" dir="ltr"><head></head></html>)

  describe "the language served" do
    test "is the first content-language tag, in lower case" do
      observation = Observation.new(200, [{"Content-Language", "FR-ca, en"}], @page)

      assert observation.content_language == "fr-ca"
      assert observation.html_lang == "de-ch"
      assert observation.language == "fr-ca"
    end

    test "falls back to the lang of the html element" do
      observation = Observation.new(200, [], @page)

      assert observation.content_language == nil
      assert observation.language == "de-ch"
    end

    test "reads an unquoted or single-quoted lang" do
      assert Observation.new(200, [], "<html lang=ja>").language == "ja"
      assert Observation.new(200, [], "<HTML LANG='pt-BR'>").language == "pt-br"
    end

    test "is nil when the page declares none" do
      for body <- ["", "<html><body lang=\"fr\"></body></html>", "plain text", <<255, 254>>] do
        assert Observation.new(200, [], body).language == nil
      end
    end
  end

  describe "how the response varies and may be stored" do
    test "combines several vary lines and counts them" do
      headers = [{"vary", "accept-language"}, {"vary", "Accept-Encoding, Cookie"}]
      observation = Observation.new(200, headers, "")

      assert observation.vary == ["accept-language", "accept-encoding", "cookie"]
      assert observation.vary_lines == 2
    end

    test "has no vary members and no lines when the header is absent" do
      observation = Observation.new(200, [], "")

      assert observation.vary == []
      assert observation.vary_lines == 0
    end

    test "reads the cache-control directives" do
      headers = [{"cache-control", "max-age=0, private, must-revalidate"}]

      assert Observation.new(200, headers, "").cache_control ==
               ["max-age=0", "private", "must-revalidate"]
    end

    test "notes a set-cookie" do
      assert Observation.new(200, [{"set-cookie", "_app_key=abc; path=/"}], "").set_cookie?
      refute Observation.new(200, [], "").set_cookie?
    end
  end

  describe "the cache" do
    test "is named and its status read" do
      headers = [
        {"cf-cache-status", "MISS"},
        {"age", "0"},
        {"date", "Tue, 17 Nov 2026 00:00:00 GMT"}
      ]

      observation = Observation.new(200, headers, "")

      assert observation.cache_vendor == :cloudflare
      assert observation.cache_status == :miss
      assert observation.age == 0
      assert observation.date == "Tue, 17 Nov 2026 00:00:00 GMT"
    end

    test "has a nil age for a value that is not a count of seconds" do
      for value <- ["", "soon", "-1", "1.5"] do
        assert Observation.new(200, [{"age", value}], "").age == nil
      end
    end
  end

  test "the body hash tells two bodies apart" do
    first = Observation.new(200, [], "bonjour")
    second = Observation.new(200, [], "guten Tag")

    assert first.body_hash == Observation.new(200, [], "bonjour").body_hash
    refute first.body_hash == second.body_hash
    assert byte_size(first.body_hash) == 64
  end
end
