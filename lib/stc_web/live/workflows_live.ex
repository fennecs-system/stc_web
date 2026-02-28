defmodule StcWeb.WorkflowsLive do
  use Phoenix.LiveView

  import StcWeb.Components
  alias StcWeb.Inspector
  alias Phoenix.LiveView.JS

  @refresh_ms 2_000

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    selected_id = Map.get(params, "id")

    socket =
      socket
      |> assign(selected_id: selected_id, dag: nil, events_by_task: %{}, workflow_status: :pending)
      |> load_workflow_list()
      |> maybe_load_workflow(selected_id)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, maybe_load_workflow(socket, id)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, selected_id: nil, dag: nil, events_by_task: %{})}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    socket =
      socket
      |> load_workflow_list()
      |> maybe_load_workflow(socket.assigns.selected_id)

    {:noreply, socket}
  end

  defp load_workflow_list(socket) do
    ids = Inspector.list_workflow_ids_from_events()

    workflows =
      Enum.map(ids, fn id ->
        events = Inspector.fetch_events_for_workflow(id)
        {id, Inspector.workflow_status(events)}
      end)

    assign(socket, workflows: workflows)
  end

  defp maybe_load_workflow(socket, nil), do: socket

  defp maybe_load_workflow(socket, id) do
    events = Inspector.fetch_events_for_workflow(id)
    events_by_task = Enum.group_by(events, &Map.get(&1, :task_id)) |> Map.delete(nil)
    dag = Inspector.build_program_dag(id)
    status = Inspector.workflow_status(events)

    assign(socket,
      selected_id: id,
      events_by_task: events_by_task,
      dag: dag,
      workflow_status: status
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.nav prefix={@stc_prefix} current={:workflows} />

      <div class="stc-page">
        <div class="stc-page-title">:: <span>workflows</span></div>

        <div style="display:flex; gap:24px; align-items:flex-start">
          <div style="min-width:260px; flex-shrink:0">
            <div class="stc-section-title">workflows (<%= length(@workflows) %>)</div>
            <%= if @workflows == [] do %>
              <div class="stc-empty">no workflows found in event log</div>
            <% else %>
              <table class="stc-table">
                <thead>
                  <tr>
                    <th></th>
                    <th>workflow id</th>
                    <th>status</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {id, status} <- @workflows do %>
                    <tr
                      phx-click={JS.patch("#{@stc_prefix}/workflows/#{id}")}
                      style={"cursor:pointer;#{if @selected_id == id, do: "background:var(--bg-2)"}"}
                    >
                      <td style="width:16px; padding-right:0">
                        <%= if @selected_id == id do %>
                          <span style="color:var(--green)">▶</span>
                        <% end %>
                      </td>
                      <td><span class="id"><%= id %></span></td>
                      <td><span class={"wf-status-#{status}"}><%= status %></span></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>

          <%= if @selected_id do %>
            <div style="flex:1; min-width:0; overflow:hidden">
              <div class="stc-section-title" style="display:flex; align-items:center; gap:12px">
                <span><%= @selected_id %></span>
                <span class={"wf-status-#{@workflow_status}"}><%= @workflow_status %></span>
                <span class="dim" style="font-size:10px">
                  <%= map_size(@events_by_task) %> tasks &nbsp;·&nbsp;
                  <%= @events_by_task |> Map.values() |> List.flatten() |> length() %> events
                </span>
              </div>

              <%= if @dag == nil && map_size(@events_by_task) == 0 do %>
                <div class="stc-empty">no program or events found for this workflow</div>
              <% else %>
                <%= if @dag do %>
                  <div style="margin-bottom:8px; font-size:10px; color:var(--fg-dim); letter-spacing:1px">
                    PROGRAM STRUCTURE + EVENTS
                  </div>
                  <div class="dag-root">
                    <.dag_node node={@dag} events_by_task={@events_by_task} />
                  </div>
                <% else %>
                  <div style="margin-bottom:8px; font-size:10px; color:var(--fg-dim); letter-spacing:1px">
                    EVENT TRACE (no program structure available)
                  </div>
                  <div class="dag-root">
                    <div class="dag-sequence">
                      <%= for {task_id, task_events} <- Enum.sort_by(@events_by_task, fn {_, evs} ->
                            evs |> List.first() |> Map.get(:timestamp) |> to_unix()
                          end) do %>
                        <.dag_node
                          node={{:task, task_id, task_module(task_events)}}
                          events_by_task={@events_by_task}
                        />
                        <div class="dag-v-connector"></div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp task_module(events) do
    Enum.find_value(events, fn
      %Stc.Event.Ready{module: mod} -> mod
      _ -> nil
    end)
  end

  defp to_unix(nil), do: 0
  defp to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)
  defp to_unix(_), do: 0
end
