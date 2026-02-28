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

  plug Plug.Session, @session_options
  plug StcWeb.Dev.Router
end
