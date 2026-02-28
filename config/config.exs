import Config

config :phoenix, :json_library, JSON

import_config "#{config_env()}.exs"
