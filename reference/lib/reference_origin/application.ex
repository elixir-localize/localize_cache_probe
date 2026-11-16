defmodule ReferenceOrigin.Application do
  @moduledoc """
  Starts the reference origin's two web servers under a supervisor.

  The origin itself listens on the port in the `PORT` environment
  variable, or on 4010. The same origin with `PlugHTTPCache` in front
  listens on the port above it.

  """

  use Application

  @default_port 4010

  @impl Application
  def start(_type, _arguments) do
    children = [
      listener(:origin, ReferenceOrigin.Router, port()),
      listener(:cached, ReferenceOrigin.Cached, cached_port())
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ReferenceOrigin.Supervisor)
  end

  @doc """
  Returns the port the origin listens on.

  ### Returns

  * The integer in the `PORT` environment variable, or `4010` when it is
    unset or is not a port number.

  ### Examples

      iex> is_integer(ReferenceOrigin.Application.port())
      true

  """
  @spec port() :: pos_integer()
  def port do
    case Integer.parse(System.get_env("PORT", "")) do
      {port, ""} when port > 0 and port < 65_535 -> port
      _other -> @default_port
    end
  end

  @doc """
  Returns the port the origin behind `PlugHTTPCache` listens on.

  ### Returns

  * The port above `port/0`.

  ### Examples

      iex> ReferenceOrigin.Application.cached_port() == ReferenceOrigin.Application.port() + 1
      true

  """
  @spec cached_port() :: pos_integer()
  def cached_port do
    port() + 1
  end

  defp listener(id, plug, port) do
    Supervisor.child_spec({Bandit, plug: plug, port: port, startup_log: false}, id: id)
  end
end
