defmodule StcWeb.Router do
  @moduledoc """
  Provides the `dashboard/2` macro for mounting the STC dashboard in any Phoenix router.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import StcWeb.Router

        scope "/" do
          pipe_through :browser
          dashboard("/stc")
        end
      end
  """

  defmacro dashboard(path, opts \\ []) do
    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session :stc_web,
          session: %{"stc_prefix" => path},
          on_mount: [StcWeb.Nav],
          root_layout: {StcWeb.Layouts, :root} do
          live "/", StcWeb.DashboardLive, :index, as: :stc_dashboard
          live "/events", StcWeb.EventsLive, :index, as: :stc_events
          live "/workflows", StcWeb.WorkflowsLive, :index, as: :stc_workflows
          live "/workflows/:id", StcWeb.WorkflowsLive, :show, as: :stc_workflow
          live "/schedulers", StcWeb.SchedulersLive, :index, as: :stc_schedulers
          live "/programs", StcWeb.ProgramsLive, :index, as: :stc_programs
        end
      end
    end
  end
end
