defmodule LocalizeCacheProbe.VisitorTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.TestOrigin
  alias LocalizeCacheProbe.Visitor

  doctest LocalizeCacheProbe.Visitor

  describe "new/2" do
    test "sends no accept-language for nil, a blank or a value that is not a string" do
      for value <- [nil, "", :fr, 1, ["fr"]] do
        visitor = Visitor.new("A", accept_language: value)

        assert visitor.accept_language == nil
        assert Visitor.request_headers(visitor) == []
      end
    end
  end

  describe "remember/2" do
    test "stores, replaces and removes cookies" do
      visitor =
        Visitor.new("A")
        |> Visitor.remember([{"set-cookie", "b=2; Path=/"}, {"Set-Cookie", "a=1"}])
        |> Visitor.remember([{"set-cookie", "a=changed; HttpOnly"}])

      assert visitor.cookies == %{"a" => "changed", "b" => "2"}

      visitor = Visitor.remember(visitor, [{"set-cookie", "a=; Path=/"}])
      assert visitor.cookies == %{"b" => "2"}

      visitor = Visitor.remember(visitor, [{"set-cookie", "b=gone; Max-Age = 0"}])
      assert visitor.cookies == %{}
    end

    test "keeps an equals sign inside a value" do
      visitor =
        Visitor.remember(Visitor.new("A"), [{"set-cookie", "_app_key=SFMyNTY=.abc==; path=/"}])

      assert visitor.cookies == %{"_app_key" => "SFMyNTY=.abc=="}
    end

    test "ignores a line with no name and value" do
      headers = [{"set-cookie", ""}, {"set-cookie", "novalue"}, {"set-cookie", "=orphan; Path=/"}]

      assert Visitor.remember(Visitor.new("A"), headers).cookies == %{}
    end

    test "sends the cookies it holds in order of name" do
      visitor =
        Visitor.remember(Visitor.new("A", accept_language: "de"), [
          {"set-cookie", "b=2"},
          {"set-cookie", "a=1"}
        ])

      assert Visitor.request_headers(visitor) == [
               {"accept-language", "de"},
               {"cookie", "a=1; b=2"}
             ]
    end
  end

  describe "visit/2" do
    test "sends the visitor's headers, keeps the cookie and observes the response" do
      first =
        TestOrigin.response(
          200,
          [
            {"Content-Language", "de"},
            {"Vary", "cookie"},
            {"Set-Cookie", "_app_key=abc; path=/"}
          ],
          "<html lang=\"de\">"
        )

      second = TestOrigin.response(200, [{"Content-Language", "de"}, {"Age", "3"}])
      url = TestOrigin.start([first, second])
      visitor = Visitor.new("B", accept_language: "fr")

      assert {:ok, visitor, observation} = Visitor.visit(visitor, url <> "/?locale=de")
      assert visitor.cookies == %{"_app_key" => "abc"}
      assert observation.language == "de"
      assert observation.vary == ["cookie"]
      assert observation.set_cookie?

      assert_receive {:request, request}
      assert request =~ ~r/accept-language: fr\r\n/i
      refute request =~ ~r/\r\ncookie:/i

      assert {:ok, _visitor, observation} = Visitor.visit(visitor, url <> "/")
      assert observation.cache_status == :hit

      assert_receive {:request, request}
      assert request =~ ~r/\r\ncookie: _app_key=abc\r\n/i
    end

    test "returns the error when the request cannot be made" do
      assert {:error, %ArgumentError{}} = Visitor.visit(Visitor.new("A"), "")
    end
  end
end
