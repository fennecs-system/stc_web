defmodule StcWeb.DashboardLive do
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
    counts = Inspector.event_counts()
    schedulers = Inspector.list_schedulers()

    active_count =
      Enum.sum(for {_id, _pid, state} <- schedulers, state != nil do
        map_size(state.active_tasks)
      end)

    pending_count =
      Enum.sum(for {_id, _pid, state} <- schedulers, state != nil do
        length(state.pending_ready)
      end)

    recent = Inspector.recent_events(20)

    assign(socket,
      counts: counts,
      total_events: Enum.sum(Map.values(counts)),
      scheduler_count: length(schedulers),
      active_count: active_count,
      pending_count: pending_count,
      recent_events: recent
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.nav prefix={@stc_prefix} current={:dashboard} />

      <div class="stc-page">
        <div class="stc-page-title">:: <span>overview</span></div>

        <div class="stc-stats">
          <div class="stc-stat">
            <div class="stc-stat-label">total events</div>
            <div class="stc-stat-value"><%= @total_events %></div>
          </div>
          <div class="stc-stat">
            <div class="stc-stat-label">schedulers</div>
            <div class="stc-stat-value blue"><%= @scheduler_count %></div>
          </div>
          <div class="stc-stat">
            <div class="stc-stat-label">active tasks</div>
            <div class="stc-stat-value amber"><%= @active_count %></div>
          </div>
          <div class="stc-stat">
            <div class="stc-stat-label">pending ready</div>
            <div class="stc-stat-value"><%= @pending_count %></div>
          </div>
          <%= for {type, count} <- Enum.sort(@counts) do %>
            <div class="stc-stat">
              <div class="stc-stat-label"><%= type %></div>
              <div class={"stc-stat-value #{event_value_class(type)}"}><%= count %></div>
            </div>
          <% end %>
        </div>

        <div class="stc-section">
          <div class="stc-section-title">recent events</div>
          <%= if @recent_events == [] do %>
            <div class="stc-empty">no events recorded yet</div>
          <% else %>
            <table class="stc-table">
              <thead>
                <tr>
                  <th>type</th>
                  <th>workflow</th>
                  <th>task</th>
                  <th>time</th>
                </tr>
              </thead>
              <tbody>
                <%= for event <- @recent_events do %>
                  <tr>
                    <td><span class={"evt evt-#{Inspector.event_type_name(event)}"}><%= Inspector.event_type_name(event) %></span></td>
                    <td><span class="id"><%= Inspector.short_id(event_workflow_id(event)) %></span></td>
                    <td><span class="id"><%= Inspector.short_id(event_task_id(event)) %></span></td>
                    <td><span class="ts"><%= format_ts(event_ts(event)) %></span></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp event_value_class("failed"), do: "red"
  defp event_value_class("completed"), do: "green"
  defp event_value_class("started"), do: "blue"
  defp event_value_class(_), do: ""

  defp event_workflow_id(e) do
    Map.get(e, :workflow_id)
  rescue
    _ -> nil
  end

  defp event_task_id(e) do
    Map.get(e, :task_id)
  rescue
    _ -> nil
  end

  defp event_ts(e) do
    Map.get(e, :timestamp)
  rescue
    _ -> nil
  end

  defp format_ts(nil), do: "—"
  defp format_ts(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_ts(_), do: "—"

end
