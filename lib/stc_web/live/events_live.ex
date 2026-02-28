defmodule StcWeb.EventsLive do
  use Phoenix.LiveView

  import StcWeb.Components
  alias StcWeb.Inspector

  @page_size 50
  @refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    socket =
      socket
      |> assign(filter_type: "all", filter_workflow: "", filter_task: "")
      |> assign(page: 1, cursor_stack: [], current_cursor: nil)
      |> load_page(Inspector.event_origin(), 1)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"type" => type, "workflow" => wf, "task" => task}, socket) do
    socket =
      socket
      |> assign(filter_type: type, filter_workflow: wf, filter_task: task, page: 1, cursor_stack: [])
      |> load_page(Inspector.event_origin(), 1)

    {:noreply, socket}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    %{next_cursor: next_cursor, current_cursor: cursor, page: page, cursor_stack: stack} = socket.assigns

    socket =
      socket
      |> assign(page: page + 1, cursor_stack: [cursor | stack])
      |> load_page(next_cursor, page + 1)

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    %{page: page, cursor_stack: stack} = socket.assigns

    {prev_cursor, rest} = List.pop_at(stack, 0)

    socket =
      socket
      |> assign(page: page - 1, cursor_stack: rest)
      |> load_page(prev_cursor || Inspector.event_origin(), page - 1)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    # Only auto-refresh on page 1
    socket =
      if socket.assigns.page == 1 do
        load_page(socket, Inspector.event_origin(), 1)
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_page(socket, cursor, _page) do
    {:ok, events, next_cursor} = Inspector.fetch_events(cursor, limit: @page_size)
    {:ok, peek, _} = Inspector.fetch_events(next_cursor, limit: 1)

    filtered = apply_filters(events, socket.assigns)

    assign(socket,
      events: filtered,
      raw_events: events,
      next_cursor: next_cursor,
      current_cursor: cursor,
      has_next: peek != []
    )
  end

  defp apply_filters(events, assigns) do
    events
    |> filter_by_type(assigns.filter_type)
    |> filter_by_field(:workflow_id, assigns.filter_workflow)
    |> filter_by_field(:task_id, assigns.filter_task)
  end

  defp filter_by_type(events, "all"), do: events

  defp filter_by_type(events, type) do
    Enum.filter(events, fn e -> Inspector.event_type_name(e) == type end)
  end

  defp filter_by_field(events, _field, ""), do: events

  defp filter_by_field(events, field, query) do
    Enum.filter(events, fn e ->
      value = Map.get(e, field, "")
      is_binary(value) && String.contains?(value, query)
    end)
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.nav prefix={@stc_prefix} current={:events} />

      <div class="stc-page">
        <div class="stc-page-title">:: <span>event log</span></div>

        <form phx-change="filter" class="stc-filters">
          <label>type</label>
          <select name="type" class="stc-select">
            <%= for t <- ~w(all ready started completed failed pending preempted progress) do %>
              <option value={t} selected={@filter_type == t}><%= t %></option>
            <% end %>
          </select>
          <label>workflow</label>
          <input type="text" name="workflow" value={@filter_workflow} placeholder="filter…" class="stc-input" style="width:160px" />
          <label>task</label>
          <input type="text" name="task" value={@filter_task} placeholder="filter…" class="stc-input" style="width:160px" />
        </form>

        <%= if @events == [] do %>
          <div class="stc-empty">no events match</div>
        <% else %>
          <table class="stc-table">
            <thead>
              <tr>
                <th>type</th>
                <th>workflow id</th>
                <th>task id</th>
                <th>detail</th>
                <th>time</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr>
                  <td><span class={"evt evt-#{Inspector.event_type_name(event)}"}><%= Inspector.event_type_name(event) %></span></td>
                  <td><span class="id"><%= Map.get(event, :workflow_id, "—") %></span></td>
                  <td><span class="id"><%= Map.get(event, :task_id, "—") %></span></td>
                  <td class="dim"><%= event_detail(event) %></td>
                  <td><span class="ts"><%= format_ts(Map.get(event, :timestamp)) %></span></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>

        <%= if @page > 1 || @has_next do %>
          <div class="stc-pagination">
            <span class="dim">page <%= @page %></span>
            <span class="dim">·</span>
            <span class="dim"><%= length(@events) %> shown</span>
            <%= if @page > 1 do %>
              <button class="stc-btn" phx-click="prev_page">← prev</button>
            <% end %>
            <%= if @has_next do %>
              <button class="stc-btn" phx-click="next_page">next →</button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp event_detail(%Stc.Event.Completed{attempt: a, result: r}) do
    "attempt=#{a} result=#{inspect(r, limit: 3)}"
  end

  defp event_detail(%Stc.Event.Failed{reason: reason, attempt: a, retriable: ret}) do
    "attempt=#{a} retriable=#{ret} reason=#{inspect(reason, limit: 3)}"
  end

  defp event_detail(%Stc.Event.Started{agent_ids: ids}) do
    "agents=[#{Enum.join(ids || [], ", ")}]"
  end

  defp event_detail(%Stc.Event.Ready{module: mod}) do
    "module=#{inspect(mod)}"
  end

  defp event_detail(%Stc.Event.Progress{progress: p}) do
    "#{inspect(p, limit: 3)}"
  end

  defp event_detail(_), do: ""

  defp format_ts(nil), do: "—"
  defp format_ts(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_ts(_), do: "—"

end
