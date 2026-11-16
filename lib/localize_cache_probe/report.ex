defmodule LocalizeCacheProbe.Report do
  @moduledoc """
  Formats the results of the scenarios as text for a terminal.

  The primary API is `format/2`. The report names the page and the
  cache, gives what the cache's vendor documents about `vary` where that
  is known, and then lists each scenario with its verdict and a table of
  the requests made.

  A response whose `vary` arrived on more than one header line says so
  in the table, since a cache has to combine the lines to honour them.

  """

  alias LocalizeCacheProbe.Cache
  alias LocalizeCacheProbe.Scenario
  alias LocalizeCacheProbe.Target

  # The verdicts that mean a visitor was failed are in capitals: they were
  # served something that belongs to someone else, or their choice was lost.
  @verdicts %{
    correct: "correct",
    wrong_language: "WRONG LANGUAGE",
    reused: "reused",
    not_reused: "not reused",
    not_cached: "not cached",
    shared: "shared",
    not_shared: "not shared",
    shared_cookie: "SHARED COOKIE",
    choice_lost: "CHOICE LOST",
    skipped: "skipped",
    inconclusive: "inconclusive"
  }

  @columns ["visitor", "asks for", "request", "status", "language", "vary", "cache"]
  @absent "-"

  @doc """
  Formats a target and its scenario results as a report.

  ### Arguments

  * `target` is the `t:LocalizeCacheProbe.Target.t/0` that was probed.

  * `results` is a list of `t:LocalizeCacheProbe.Scenario.result/0`.

  ### Returns

  * The report as a string, without a trailing newline.

  ### Examples

      iex> {:ok, target} = LocalizeCacheProbe.Target.new("https://example.com/", locales: ["fr", "de"])
      iex> report = LocalizeCacheProbe.Report.format(target, [])
      iex> String.split(report, "\\n")
      ["Page:    https://example.com/", "Locales: fr asked for, de stored", "Cache:   not recognised"]

  """
  @spec format(Target.t(), [Scenario.result()]) :: String.t()
  def format(%Target{url: url, locales: [asked, stored | _rest]}, results)
      when is_list(results) do
    heading = [
      "Page:    #{url}",
      "Locales: #{asked} asked for, #{stored} stored"
      | cache_lines(vendor(results))
    ]

    scenarios =
      results
      |> Enum.with_index(1)
      |> Enum.flat_map(&scenario_lines/1)

    Enum.join(heading ++ scenarios, "\n")
  end

  # The cache is named by the first response that identifies one.
  defp vendor(results) do
    results
    |> Enum.flat_map(& &1.steps)
    |> Enum.map(& &1.observation.cache_vendor)
    |> Enum.find(:unknown, &(&1 != :unknown))
  end

  defp cache_lines(:unknown) do
    ["Cache:   not recognised"]
  end

  defp cache_lines(vendor) do
    case Cache.vary_note(vendor) do
      {:ok, note} -> ["Cache:   #{vendor}", "         #{note.summary}", "         #{note.source}"]
      :error -> ["Cache:   #{vendor}"]
    end
  end

  defp scenario_lines({result, number}) do
    [
      "",
      "#{number}. #{result.title}",
      "   Verdict: #{Map.get(@verdicts, result.verdict, "unknown")}",
      "   #{result.summary}"
      | table(result.steps)
    ]
  end

  defp table([]) do
    []
  end

  defp table([_ | _] = steps) do
    rows = [@columns | Enum.map(steps, &row/1)]
    widths = widths(rows)

    ["" | Enum.map(rows, &line(&1, widths))]
  end

  defp row(%{visitor: visitor, url: url, observation: observation} = step) do
    [
      visitor,
      Map.get(step, :accept_language) || @absent,
      request(url),
      Integer.to_string(observation.status),
      observation.language || @absent,
      vary(observation.vary, observation.vary_lines),
      Atom.to_string(observation.cache_status)
    ]
  end

  defp request(url) do
    %URI{path: path, query: query} = URI.parse(url)
    path = path || "/"

    if is_nil(query) do
      path
    else
      path <> "?" <> query
    end
  end

  defp vary([], _lines) do
    @absent
  end

  defp vary([_ | _] = members, lines) when lines > 1 do
    Enum.join(members, ", ") <> " (#{lines} lines)"
  end

  defp vary([_ | _] = members, _lines) do
    Enum.join(members, ", ")
  end

  defp widths(rows) do
    rows
    |> Enum.zip_with(& &1)
    |> Enum.map(&longest/1)
  end

  defp longest(cells) do
    cells
    |> Enum.map(&String.length/1)
    |> Enum.max()
  end

  defp line(cells, widths) do
    padded =
      cells
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing(cell, width) end)

    String.trim_trailing("   " <> padded)
  end
end
