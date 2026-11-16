defmodule ReferenceOrigin.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :reference_origin,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ReferenceOrigin.Application, []}
    ]
  end

  # `localize_web` comes from the sibling checkout so that the origin
  # runs the code under discussion, released or not.
  defp deps do
    [
      {:localize_web, path: "../../localize_web"},
      {:plug, "~> 1.19"},
      {:bandit, "~> 1.14"},
      {:http_cache, "~> 1.0"},
      {:plug_http_cache, "~> 1.0"},
      {:http_cache_store_memory, "~> 1.0"}
    ]
  end
end
