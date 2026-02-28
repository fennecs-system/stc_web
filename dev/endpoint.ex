defmodule StcWeb.Dev.Endpoint do
  use Phoenix.Endpoint, otp_app: :stc_web

  @session_options [
    store: :cookie,
    key: "_stc_web_dev_key",
    signing_salt: "stc_dev_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader

  plug Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    only: ["phoenix.js"]

  plug Plug.Static,
    at: "/assets/lv",
    from: {:phoenix_live_view, "priv/static"},
    only: ["phoenix_live_view.js"]

  plug Plug.Session, @session_options
  plug StcWeb.Dev.Router
end
