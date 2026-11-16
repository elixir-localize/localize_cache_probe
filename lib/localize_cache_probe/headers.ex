defmodule LocalizeCacheProbe.Headers do
  @moduledoc """
  Reads response headers held as a list of `{name, value}` pairs.

  A response may repeat a header on several lines, and the probe needs
  to see each one: `vary` set on two lines is one of the cases it tests.
  The list keeps every line in the order it was received. Names are
  matched without regard to case, and an entry that is not a pair of
  strings is ignored.

  """

  @typedoc "Response headers as name and value pairs, one per header line."
  @type t :: [{String.t(), String.t()}]

  @doc """
  Returns the value of the first line of a header.

  ### Arguments

  * `headers` is a list of `{name, value}` response headers.

  * `name` is the header name in lower case.

  ### Returns

  * The value of the first matching line, or

  * `nil` when the header is absent.

  ### Examples

      iex> LocalizeCacheProbe.Headers.first([{"Age", "42"}], "age")
      "42"

      iex> LocalizeCacheProbe.Headers.first([], "age")
      nil

  """
  @spec first(t(), String.t()) :: String.t() | nil
  def first(headers, name) when is_list(headers) and is_binary(name) do
    Enum.find_value(headers, &value(&1, name))
  end

  @doc """
  Returns the value of every line of a header, in the order received.

  ### Arguments

  * `headers` is a list of `{name, value}` response headers.

  * `name` is the header name in lower case.

  ### Returns

  * A list of values, which is empty when the header is absent.

  ### Examples

      iex> headers = [{"vary", "accept-language"}, {"vary", "Accept-Encoding"}]
      iex> LocalizeCacheProbe.Headers.all(headers, "vary")
      ["accept-language", "Accept-Encoding"]

  """
  @spec all(t(), String.t()) :: [String.t()]
  def all(headers, name) when is_list(headers) and is_binary(name) do
    headers
    |> Enum.map(&value(&1, name))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns the members of a comma-separated header across all its lines.

  Each member is trimmed and put in lower case, empty members are left
  out, and a member that appears twice is kept once. This is how a
  recipient combines several `vary` or `cache-control` lines.

  ### Arguments

  * `headers` is a list of `{name, value}` response headers.

  * `name` is the header name in lower case.

  ### Returns

  * A list of members, which is empty when the header is absent.

  ### Examples

      iex> headers = [{"vary", "accept-language"}, {"vary", "Cookie, Accept-Language"}]
      iex> LocalizeCacheProbe.Headers.members(headers, "vary")
      ["accept-language", "cookie"]

  """
  @spec members(t(), String.t()) :: [String.t()]
  def members(headers, name) when is_list(headers) and is_binary(name) do
    headers
    |> all(name)
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&normalise/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalise(member) do
    member
    |> String.trim()
    |> String.downcase()
  end

  defp value({header_name, value}, name) when is_binary(header_name) and is_binary(value) do
    if String.downcase(header_name) == name do
      value
    else
      nil
    end
  end

  defp value(_other, _name) do
    nil
  end
end
