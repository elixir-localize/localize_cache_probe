defmodule Mix.Tasks.Cache.ProbeTest do
  # Not async: the test replaces Mix's shell, which is global.
  use ExUnit.Case, async: false

  alias LocalizeCacheProbe.TestApplication
  alias Mix.Tasks.Cache.Probe

  setup do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)

    :ok
  end

  test "prints a report of every scenario, skipping those without their option" do
    url = TestApplication.start(:honours_vary)

    assert Probe.run([url <> "/pricing", "--locales", "fr, de"]) == :ok

    assert_received {:mix_shell, :info, [report]}
    assert report =~ "Page:    #{url}/pricing"

    assert report =~
             "1. Two visitors whose browsers ask for different locales\n   Verdict: correct"

    assert report =~ "/pricing?locale=de"
    assert report =~ "Verdict: not shared"
    assert report =~ "8. Two new visitors, when the first response sets a cookie"

    assert report =~
             "6. Two visitors whose browsers ask for different regions of one language\n" <>
               "   Verdict: skipped"

    assert report =~ "7. Two visitors at the page with a locale in its URL\n   Verdict: skipped"
  end

  test "runs the region and localized-URL scenarios when given their options" do
    url = TestApplication.start(:honours_vary)

    arguments = [
      url <> "/pricing",
      "--locales",
      "fr,de",
      "--regions",
      "fr-FR, fr-CH",
      "--localized-url",
      url <> "/{locale}/pricing"
    ]

    assert Probe.run(arguments) == :ok

    assert_received {:mix_shell, :info, [report]}
    refute report =~ "Verdict: skipped"
    assert report =~ "fr-CH"
    assert report =~ "/de/pricing"

    assert report =~ "7. Two visitors at the page with a locale in its URL\n   Verdict: shared"
  end

  test "exits with status 1 when a visitor is served the wrong language from a cache" do
    url = TestApplication.start(:ignores_vary)

    assert catch_exit(Probe.run([url <> "/pricing", "--locales", "fr,de"])) == {:shutdown, 1}

    assert_received {:mix_shell, :info, [report]}
    assert report =~ "Verdict: WRONG LANGUAGE"
    assert report =~ "Verdict: SHARED COOKIE"
  end

  test "raises with the usage for arguments it cannot use" do
    assert_raise Mix.Error, ~r/expected :locales.*\nUsage: mix cache.probe/s, fn ->
      Probe.run(["https://example.com/"])
    end

    assert_raise Mix.Error, ~r/expected one URL/, fn ->
      Probe.run(["--locales", "fr,de"])
    end

    assert_raise Mix.Error, ~r/expected one URL/, fn ->
      Probe.run(["https://example.com/a", "https://example.com/b", "--locales", "fr,de"])
    end

    assert_raise Mix.Error, ~r/unknown option --nope/, fn ->
      Probe.run(["https://example.com/", "--locales", "fr,de", "--nope"])
    end

    assert_raise Mix.Error, ~r/expected :url/, fn ->
      Probe.run(["not-a-url", "--locales", "fr,de"])
    end

    assert_raise Mix.Error, ~r/expected :regions/, fn ->
      Probe.run(["https://example.com/", "--locales", "fr,de", "--regions", "fr-FR"])
    end

    assert_raise Mix.Error, ~r/expected :localized_url/, fn ->
      Probe.run(["https://example.com/", "--locales", "fr,de", "--localized-url", "/de/x"])
    end
  end
end
