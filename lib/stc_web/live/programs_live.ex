defmodule StcWeb.ProgramsLive do
  use Phoenix.LiveView

  import StcWeb.Components
  alias StcWeb.Inspector

  @refresh_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    socket =
      socket
      |> assign(selected_id: nil, program: nil)
      |> assign_workflow_ids()

    {:ok, socket}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    program =
      case Inspector.get_program(id) do
        {:ok, p} -> p
        _ -> nil
      end

    {:noreply, assign(socket, selected_id: id, program: program)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign_workflow_ids(socket)}
  end

  defp assign_workflow_ids(socket) do
    assign(socket, workflow_ids: Inspector.list_workflow_ids())
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_ms)

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.nav prefix={@stc_prefix} current={:programs} />

      <div class="stc-page">
        <div class="stc-page-title">:: <span>program store</span></div>

        <div style="display:flex; gap:20px; align-items:flex-start">
          <div style="min-width:280px; flex-shrink:0">
            <div class="stc-section-title">workflows (<%= length(@workflow_ids) %>)</div>
            <%= if @workflow_ids == [] do %>
              <div class="stc-empty">no programs stored</div>
            <% else %>
              <table class="stc-table">
                <thead>
                  <tr>
                    <th>workflow id</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for id <- @workflow_ids do %>
                    <tr
                      phx-click="select"
                      phx-value-id={id}
                      style={"cursor:pointer; #{if @selected_id == id, do: "background:var(--bg-2)"}"}
                    >
                      <td>
                        <%= if @selected_id == id do %>
                          <span style="color:var(--amber)">▶ </span>
                        <% end %>
                        <span class="id"><%= id %></span>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </div>

          <%= if @selected_id do %>
            <div style="flex:1; min-width:0">
              <div class="stc-section-title">
                program — <span style="color:var(--fg-mid)"><%= @selected_id %></span>
              </div>
              <%= if @program do %>
                <div class="stc-program-tree"><%= inspect(@program, pretty: true, limit: 200, printable_limit: 200) %></div>
              <% else %>
                <div class="stc-empty">program not found or could not be decoded</div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

end
