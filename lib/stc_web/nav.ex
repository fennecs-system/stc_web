defmodule StcWeb.Nav do
  @moduledoc """
  LiveView `on_mount` hook that injects the dashboard prefix into socket assigns,
  enabling all LiveView pages to build correct navigation links regardless of where
  the dashboard is mounted in the host router.
  """

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    prefix = Map.get(session, "stc_prefix", "/stc")
    {:cont, assign(socket, :stc_prefix, prefix)}
  end
end
