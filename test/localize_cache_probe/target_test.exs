defmodule LocalizeCacheProbe.TargetTest do
  use ExUnit.Case, async: true

  alias LocalizeCacheProbe.Target

  doctest LocalizeCacheProbe.Target

  @url "https://example.com/pricing"

  describe "new/2" do
    test "accepts a URL with two locales and fills the defaults" do
      assert {:ok, target} = Target.new(@url, locales: ["fr", "de-CH"])
      assert target.url == @url
      assert target.locales == ["fr", "de-CH"]
      assert target.param == "locale"
      assert target.choose_url == nil
    end

    test "rejects a URL it cannot request" do
      for url <- ["", "example.com", "ftp://example.com/", "http://", nil, :url, 1] do
        assert {:error, %ArgumentError{message: message}} = Target.new(url, locales: ["fr", "de"])
        assert message =~ "expected :url"
      end
    end

    test "rejects locales that are missing, too few, repeated or unsafe in a URL" do
      for locales <- [
            nil,
            [],
            ["fr"],
            ["fr", "fr"],
            "fr,de",
            ["fr", ""],
            ["fr", "de&x=1"],
            ["fr", :de],
            ["fr", "de/"]
          ] do
        assert {:error, %ArgumentError{message: message}} = Target.new(@url, locales: locales)
        assert message =~ "expected :locales"
      end
    end

    test "rejects a parameter name that is not one" do
      for param <- ["", "lo cale", "a=b", nil, :locale] do
        assert {:error, %ArgumentError{message: message}} =
                 Target.new(@url, locales: ["fr", "de"], param: param)

        assert message =~ "expected :param"
      end
    end

    test "rejects a choose URL with no placeholder or that is not a URL" do
      for template <- [
            "https://example.com/switch",
            "{locale}",
            "ftp://example.com/{locale}",
            :template,
            1
          ] do
        assert {:error, %ArgumentError{message: message}} =
                 Target.new(@url, locales: ["fr", "de"], choose_url: template)

        assert message =~ "expected :choose_url"
      end
    end
  end

  describe "the options two scenarios need" do
    test "are nil by default and kept when given" do
      assert {:ok, %{regions: nil, localized_url: nil}} = Target.new(@url, locales: ["fr", "de"])

      assert {:ok, target} =
               Target.new(@url,
                 locales: ["fr", "de"],
                 regions: ["fr-FR", "fr-CH"],
                 localized_url: "https://example.com/{locale}/pricing"
               )

      assert target.regions == ["fr-FR", "fr-CH"]
      assert Target.localized_url(target, "de") == {:ok, "https://example.com/de/pricing"}
    end

    test "localized_url/2 is :error without a template" do
      {:ok, target} = Target.new(@url, locales: ["fr", "de"])

      assert Target.localized_url(target, "de") == :error
    end

    test "rejects regions that are not two different locales" do
      for regions <- [
            [],
            ["fr-FR"],
            ["fr-FR", "fr-FR"],
            ["fr-FR", "fr-CH", "fr-CA"],
            "fr-FR",
            ["fr-FR", :x]
          ] do
        assert {:error, %ArgumentError{message: message}} =
                 Target.new(@url, locales: ["fr", "de"], regions: regions)

        assert message =~ "expected :regions"
      end
    end

    test "rejects a localized URL with no placeholder or that is not a URL" do
      for template <- ["https://example.com/de/pricing", "/{locale}/pricing", :template] do
        assert {:error, %ArgumentError{message: message}} =
                 Target.new(@url, locales: ["fr", "de"], localized_url: template)

        assert message =~ "expected :localized_url"
      end
    end
  end

  describe "choose_url/2" do
    test "adds the parameter to a URL with no query" do
      {:ok, target} = Target.new(@url, locales: ["fr", "de"])

      assert Target.choose_url(target, "de") == "https://example.com/pricing?locale=de"
    end

    test "uses the parameter name given" do
      {:ok, target} = Target.new(@url, locales: ["fr", "de"], param: "lang")

      assert Target.choose_url(target, "fr") == "https://example.com/pricing?lang=fr"
    end

    test "fills in a template" do
      {:ok, target} =
        Target.new(@url, locales: ["fr", "de"], choose_url: "https://example.com/{locale}/switch")

      assert Target.choose_url(target, "de") == "https://example.com/de/switch"
    end
  end
end
