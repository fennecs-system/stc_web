defmodule StcWeb.Dev.Application do
  @moduledoc """
  Dev application that boots STC + the StcWeb dashboard against an in-memory backend.
  Run with: iex -S mix
  """
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      # STC backends
      Stc.Backend.Memory.EventLog,
      Stc.Backend.Memory.KV,

      # Horde cluster (single node for dev)
      {Horde.Registry, name: Stc.SchedulerRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor, name: Stc.SchedulerSupervisor, strategy: :one_for_one, members: :auto},

      # Phoenix PubSub + Endpoint
      {Phoenix.PubSub, name: StcWeb.Dev.PubSub},
      StcWeb.Dev.Endpoint
    ]

    opts = [strategy: :one_for_one, name: StcWeb.Dev.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
