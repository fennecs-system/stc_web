defmodule StcWeb.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :stc_web,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    extra = [extra_applications: [:logger]]

    if Mix.env() == :dev do
      Keyword.put(extra, :mod, {StcWeb.Dev.Application, []})
    else
      extra
    end
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},

      # dev server
      {:bandit, "~> 1.0", only: :dev},
      {:phoenix_live_reload, "~> 1.2", only: :dev},

      # stc (path in dev/test; hex in prod)
      {:stc, path: "../stc", only: [:dev, :test]},
      {:horde, "~> 0.8", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      "phx.server": ["cmd --cd dev mix phx.server"],
      setup: ["deps.get"]
    ]
  end
end
