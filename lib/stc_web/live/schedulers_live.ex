defmodule StcWeb.SchedulersLive do
  use Phoenix.LiveView

  import StcWeb.Components
  alias StcWeb.Inspector

  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()
    {:ok, assign_data(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign_data(socket)}
  end

  defp assign_data(socket) do
    assign(socket, schedulers: Inspector.list_schedulers())
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.nav prefix={@stc_prefix} current={:schedulers} />

      <div class="stc-page">
        <div class="stc-page-title">:: <span>schedulers</span></div>

        <%= if @schedulers == [] do %>
          <div class="stc-empty">no schedulers running</div>
        <% else %>
          <%= for {id, pid, state} <- @schedulers do %>
            <div class="stc-scheduler-card">
              <div class="stc-scheduler-header">
                <span class="stc-scheduler-id"><%= id %></span>
                <span class="stc-scheduler-meta">pid=<%= inspect(pid) %></span>
                <%= if state do %>
                  <span class="stc-scheduler-meta">level=<%= state.level || "—" %></span>
                  <span class="stc-scheduler-meta">algo=<%= inspect(state.algorithm) %></span>
                <% end %>
              </div>

              <%= if state == nil do %>
                <div class="dim" style="font-size:11px">state unavailable</div>
              <% else %>
                <div class="stc-kv-grid">
                  <div class="stc-kv">
                    <div class="stc-kv-label">agents</div>
                    <div class="stc-kv-value"><%= length(state.agent_pool) %></div>
                  </div>
                  <div class="stc-kv">
                    <div class="stc-kv-label">stale agents</div>
                    <div class="stc-kv-value"><%= length(state.stale_agent_pool) %></div>
                  </div>
                  <div class="stc-kv">
                    <div class="stc-kv-label">active tasks</div>
                    <div class="stc-kv-value" style="color:var(--amber)"><%= map_size(state.active_tasks) %></div>
                  </div>
                  <div class="stc-kv">
                    <div class="stc-kv-label">pending ready</div>
                    <div class="stc-kv-value"><%= length(state.pending_ready) %></div>
                  </div>
                  <div class="stc-kv">
                    <div class="stc-kv-label">task locks</div>
                    <div class="stc-kv-value"><%= map_size(state.task_locks) %></div>
                  </div>
                </div>

                <%= if map_size(state.active_tasks) > 0 do %>
                  <div class="stc-section-title" style="margin-top:8px">active tasks</div>
                  <table class="stc-table">
                    <thead>
                      <tr>
                        <th>task id</th>
                        <th>executor pid</th>
                        <th>agents</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {task_id, exec_pid} <- state.active_tasks do %>
                        <tr>
                          <td><span class="id"><%= task_id %></span></td>
                          <td><span class="dim"><%= inspect(exec_pid) %></span></td>
                          <td>
                            <%= for agent_id <- Map.get(state.agent_tasks, task_id |> agent_ids_for(state), []) do %>
                              <span class="id"><%= agent_id %>&nbsp;</span>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                <% end %>

                <%= if length(state.agent_pool) > 0 do %>
                  <div class="stc-section-title" style="margin-top:12px">agent pool</div>
                  <table class="stc-table">
                    <thead>
                      <tr>
                        <th>agent id</th>
                        <th>status</th>
                        <th>running tasks</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for agent <- state.agent_pool do %>
                        <tr>
                          <td><span class="id"><%= agent.id %></span></td>
                          <td>
                            <%= cond do %>
                              <% agent_busy?(agent, state) -> %>
                                <span class="evt evt-started">busy</span>
                              <% true -> %>
                                <span class="evt evt-completed">free</span>
                            <% end %>
                          </td>
                          <td>
                            <span class="dim"><%= Enum.join(Map.get(state.agent_tasks, agent.id, []), ", ") %></span>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                <% end %>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp agent_busy?(agent, state) do
    state.agent_tasks
    |> Map.get(agent.id, [])
    |> Enum.any?()
  end

  # Returns the agent ids assigned to a given task
  defp agent_ids_for(task_id, state) do
    state.agent_tasks
    |> Enum.filter(fn {_agent_id, task_ids} -> task_id in task_ids end)
    |> Enum.map(fn {agent_id, _} -> agent_id end)
  end

end
