defmodule StcWeb.Components do
  @moduledoc false

  use Phoenix.Component

  @doc "Top navigation bar shared across all dashboard pages."
  attr :prefix, :string, required: true
  attr :current, :atom, required: true

  def nav(assigns) do
    assigns = assign(assigns, :base, String.trim_trailing(assigns.prefix, "/"))

    ~H"""
    <header class="stc-header">
      <div class="stc-logo">
        <pre class="stc-fox">
     ▃         ▃
     ██▙▂   ▂▟██
     █████▄█████
    ▟███████████▙
    ▀██▄ ███ ▄██▀
      ▜███████▛
        ▜█▄█▛</pre>
      </div>
      <nav>
        <ul class="stc-nav">
          <li><.link navigate={"#{@base}/"} class={active(@current, :dashboard)}>/dashboard</.link></li>
          <li><.link navigate={"#{@base}/events"} class={active(@current, :events)}>/events</.link></li>
          <li><.link navigate={"#{@base}/workflows"} class={active(@current, :workflows)}>/workflows</.link></li>
          <li><.link navigate={"#{@base}/schedulers"} class={active(@current, :schedulers)}>/schedulers</.link></li>
          <li><.link navigate={"#{@base}/programs"} class={active(@current, :programs)}>/programs</.link></li>
        </ul>
      </nav>
      <div class="stc-header-right">stc_web&nbsp;v0.1</div>
    </header>
    """
  end

  defp active(current, page) when current == page, do: "active"
  defp active(_, _), do: nil

  # ---------------------------------------------------------------------------
  # DAG renderer
  # ---------------------------------------------------------------------------

  @doc """
  Recursively renders a program DAG node.

  `node` is one of:
    `{:task, task_id, module}`
    `{:sequence, [node]}`
    `{:parallel, [node]}`
    `{:unfold, node}`
    `{:unknown}`
    `nil`

  `events_by_task` is a `%{task_id => [event]}` map for overlaying execution data.
  """
  attr :node, :any, required: true
  attr :events_by_task, :map, default: %{}

  def dag_node(%{node: nil} = assigns), do: ~H""

  def dag_node(%{node: {:task, task_id, mod}} = assigns) do
    assigns =
      assign(assigns,
        task_id: task_id,
        mod: mod,
        events: Map.get(assigns.events_by_task, task_id, [])
      )

    ~H"""
    <div class="dag-task" style={task_border_style(@events)}>
      <div class="dag-task-header">
        <span class={"dot #{task_dot_class(@events)}"}></span>
        <span class="dag-task-id" title={@task_id}><%= StcWeb.Inspector.short_id(@task_id) %></span>
      </div>
      <div class="dag-task-mod"><%= inspect(@mod) %></div>
      <%= if @events == [] do %>
        <div class="dag-task-no-events">no events yet</div>
      <% else %>
        <div class="dag-task-events">
          <%= for event <- @events do %>
            <div class="dag-event-row">
              <span class={"evt evt-#{StcWeb.Inspector.event_type_name(event)}"}><%= StcWeb.Inspector.event_type_name(event) %></span>
              <span class="ts"><%= format_dag_ts(Map.get(event, :timestamp)) %></span>
              <span class="dim"><%= dag_event_detail(event) %></span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def dag_node(%{node: {:sequence, nodes}} = assigns) do
    assigns = assign(assigns, :nodes, nodes)

    ~H"""
    <div class="dag-sequence">
      <%= for {node, i} <- Enum.with_index(@nodes) do %>
        <%= if i > 0 do %><div class="dag-v-connector"></div><% end %>
        <.dag_node node={node} events_by_task={@events_by_task} />
      <% end %>
    </div>
    """
  end

  def dag_node(%{node: {:parallel, nodes}} = assigns) do
    assigns = assign(assigns, :nodes, nodes)

    ~H"""
    <div class="dag-parallel-wrapper">
      <div class="dag-parallel-bar">
        <div class="dag-parallel-bar-line edge"></div>
        <%= for {_node, i} <- Enum.with_index(@nodes) do %>
          <div class="dag-parallel-bar-line"></div>
          <%= if i < length(@nodes) - 1 do %>
            <div class="dag-parallel-bar-line"></div>
          <% end %>
        <% end %>
        <div class="dag-parallel-bar-line edge"></div>
      </div>
      <div class="dag-parallel">
        <%= for node <- @nodes do %>
          <div class="dag-branch">
            <div class="dag-branch-top"></div>
            <.dag_node node={node} events_by_task={@events_by_task} />
            <div class="dag-branch-bottom"></div>
          </div>
        <% end %>
      </div>
      <div class="dag-parallel-bar">
        <div class="dag-parallel-bar-line edge"></div>
        <%= for {_node, i} <- Enum.with_index(@nodes) do %>
          <div class="dag-parallel-bar-line"></div>
          <%= if i < length(@nodes) - 1 do %>
            <div class="dag-parallel-bar-line"></div>
          <% end %>
        <% end %>
        <div class="dag-parallel-bar-line edge"></div>
      </div>
    </div>
    """
  end

  def dag_node(%{node: {:unfold, inner}} = assigns) do
    assigns = assign(assigns, :inner, inner)

    ~H"""
    <div class="dag-unfold">
      ∿ unfold
      <%= if @inner do %>
        <div class="dag-v-connector" style="margin: 4px auto"></div>
        <.dag_node node={@inner} events_by_task={@events_by_task} />
      <% end %>
    </div>
    """
  end

  def dag_node(%{node: {:unknown}} = assigns), do: ~H"<div class='dag-unknown'>…</div>"

  def dag_node(assigns), do: ~H""

  # ---------------------------------------------------------------------------
  # DAG helpers
  # ---------------------------------------------------------------------------

  defp task_border_style([]), do: ""
  defp task_border_style(events) do
    types = Enum.map(events, &StcWeb.Inspector.event_type_name/1) |> MapSet.new()
    cond do
      "completed" in types -> "border-color: var(--pink)"
      "failed"    in types -> "border-color: var(--red)"
      "started"   in types -> "border-color: var(--blue)"
      true -> ""
    end
  end

  defp task_dot_class([]), do: "dot-dim"
  defp task_dot_class(events) do
    types = Enum.map(events, &StcWeb.Inspector.event_type_name/1) |> MapSet.new()
    cond do
      "completed" in types -> "dot-pink"
      "failed"    in types -> "dot-red"
      "started"   in types -> "dot-pink"
      true -> "dot-dim"
    end
  end

  defp format_dag_ts(nil), do: ""
  defp format_dag_ts(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_dag_ts(_), do: ""

  defp dag_event_detail(%Stc.Event.Completed{attempt: a}), do: "att=#{a}"
  defp dag_event_detail(%Stc.Event.Failed{attempt: a, retriable: r}), do: "att=#{a} ret=#{r}"
  defp dag_event_detail(%Stc.Event.Started{agent_ids: ids}), do: Enum.join(ids || [], ",")
  defp dag_event_detail(_), do: ""
end
