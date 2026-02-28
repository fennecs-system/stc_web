import Config

config :stc_web, StcWeb.Dev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  debug_errors: true,
  code_reloader: true,
  live_view: [signing_salt: "stc_web_dev_lv"],
  server: true,
  live_reload: [
    patterns: [
      ~r"lib/.*(ex|heex)$",
      ~r"dev/.*(ex|heex)$"
    ]
  ],
  secret_key_base: "dev_only_secret_key_base_not_for_production_use_at_all_change_me",
  pubsub_server: StcWeb.Dev.PubSub

config :stc_web, :dev_routes, true

config :stc,
  event_log: {Stc.Backend.Memory.EventLog, []},
  kv: {Stc.Backend.Memory.KV, []}

config :logger, :console,
  format: "[$level] $message\n",
  level: :debug
