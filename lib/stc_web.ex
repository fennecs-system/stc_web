defmodule StcWeb do
  @moduledoc """
  StcWeb — a pluggable Phoenix LiveView dashboard for STC.

  ## Mounting in your router

      # router.ex
      scope "/" do
        pipe_through :browser
        StcWeb.Router.dashboard("/stc")
      end

  Then visit `/stc` to see the dashboard.
  """
end
