defmodule StcWeb.Inspector do
  @moduledoc """
  Data access layer for the STC dashboard.

  All functions are safe to call even when STC is not running — they return
  empty results rather than raising.

  NOTE: Scheduler state is currently fetched via `:sys.get_state/2`, which does
  a synchronous call to each scheduler GenServer. This is acceptable for a dev
  tool. The long-term approach is for schedulers to emit a periodic HeartbeatEvent
  that gets stored in the event log, so the dashboard reads state the same way it
  reads everything else.
  """

  alias Stc.Event
  alias Stc.Scheduler

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @doc """
  Returns the origin cursor (position before all events).
  """
  @spec event_origin() :: term()
  def event_origin do
    Stc.Event.Store.origin()
  rescue
    _ -> nil
  end

  @doc """
  Fetches up to `limit` events after `cursor`.
  Returns `{:ok, events, new_cursor}`.
  """
  @spec fetch_events(term(), keyword()) :: {:ok, [struct()], term()}
  def fetch_events(cursor, opts \\ []) do
    Stc.Event.Store.fetch(cursor, opts)
  rescue
    _ -> {:ok, [], cursor}
  end

  @doc """
  Fetches the most recent `limit` events by replaying from origin and keeping
  the tail. Useful for the dashboard overview.
  """
  @spec recent_events(pos_integer()) :: [struct()]
  def recent_events(limit \\ 50) do
    origin = event_origin()
    stream_all_events(origin, [], limit)
  end

  @doc """
  Returns a summary count map of event types across the whole log.
  """
  @spec event_counts() :: %{String.t() => non_neg_integer()}
  def event_counts do
    origin = event_origin()
    stream_all_events(origin, [], :all)
    |> Enum.frequencies_by(&event_type_name/1)
  rescue
    _ -> %{}
  end

  # ---------------------------------------------------------------------------
  # Schedulers
  # ---------------------------------------------------------------------------

  @doc """
  Returns a list of `{id, pid, state}` for all running schedulers.
  `state` may be nil if the scheduler exited between listing and introspection.
  """
  @spec list_schedulers() :: [{String.t(), pid(), Stc.Scheduler.State.t() | nil}]
  def list_schedulers do
    Scheduler.list()
    |> Enum.map(fn {id, pid} ->
      state = fetch_scheduler_state(id)
      {id, pid, state}
    end)
  rescue
    _ -> []
  end

  @doc "Returns the state for a single scheduler by id, or nil."
  @spec get_scheduler_state(String.t()) :: Stc.Scheduler.State.t() | nil
  def get_scheduler_state(id), do: fetch_scheduler_state(id)

  # ---------------------------------------------------------------------------
  # Programs
  # ---------------------------------------------------------------------------

  @doc """
  Returns all workflow IDs that have stored program state.
  """
  @spec list_workflow_ids() :: [String.t()]
  def list_workflow_ids do
    case Stc.Program.Store.list_workflow_ids() do
      {:ok, ids} -> Enum.sort(ids)
      _ -> []
    end
  rescue
    _ -> []
  end

  @doc "Returns the program for a workflow, or nil."
  @spec get_program(String.t()) :: {:ok, term()} | {:error, :not_found}
  def get_program(workflow_id) do
    Stc.Program.Store.get(workflow_id)
  rescue
    _ -> {:error, :not_found}
  end

  @doc """
  Returns all distinct workflow IDs found in the event log, in order of first
  appearance. Scans the full log so should only be used in dev/tooling contexts.
  """
  @spec list_workflow_ids_from_events() :: [String.t()]
  def list_workflow_ids_from_events do
    event_origin()
    |> stream_all_events([], :all)
    |> Enum.reduce({[], MapSet.new()}, fn event, {ids, seen} ->
      case Map.get(event, :workflow_id) do
        nil -> {ids, seen}
        id when is_binary(id) ->
          if MapSet.member?(seen, id),
            do: {ids, seen},
            else: {ids ++ [id], MapSet.put(seen, id)}
      end
    end)
    |> elem(0)
  rescue
    _ -> []
  end

  @doc """
  Returns all events for a given workflow_id in chronological order.
  Scans the full log.
  """
  @spec fetch_events_for_workflow(String.t()) :: [struct()]
  def fetch_events_for_workflow(workflow_id) do
    event_origin()
    |> stream_all_events([], :all)
    |> Enum.filter(&(Map.get(&1, :workflow_id) == workflow_id))
  rescue
    _ -> []
  end

  @doc """
  Walks the stored program tree for a workflow and returns a simplified DAG
  suitable for rendering.

  Node shapes:
    `{:task, task_id, module}`
    `{:sequence, [node]}`
    `{:parallel, [node]}`
    `{:unfold, node}`
    `{:unknown}`

  Returns `nil` if no program is stored or the tree cannot be walked.

  NOTE: Calls continuations with `nil`/dummy values — safe for tree-shape
  extraction but not for execution.
  """
  @spec build_program_dag(String.t()) :: term() | nil
  def build_program_dag(workflow_id) do
    case Stc.Program.Store.get(workflow_id) do
      {:ok, program} -> walk_dag(program, 30)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Computes a summary status for a workflow given its events.
  Returns `:running | :completed | :failed | :pending`.
  """
  @spec workflow_status([struct()]) :: :running | :completed | :failed | :pending
  def workflow_status([]), do: :pending

  def workflow_status(events) do
    by_task =
      Enum.group_by(events, &Map.get(&1, :task_id))
      |> Enum.reject(fn {k, _} -> is_nil(k) end)
      |> Map.new()

    statuses =
      for {_task_id, task_events} <- by_task do
        types = Enum.map(task_events, &event_type_name/1) |> MapSet.new()

        cond do
          "completed" in types -> :completed
          "failed" in types -> :failed
          "started" in types -> :running
          true -> :pending
        end
      end

    cond do
      :running in statuses -> :running
      :failed in statuses -> :failed
      Enum.all?(statuses, &(&1 == :completed)) -> :completed
      true -> :pending
    end
  end

  # ---------------------------------------------------------------------------
  # DAG walker (private)
  # ---------------------------------------------------------------------------

  defp walk_dag(_, 0), do: {:unknown}
  defp walk_dag({:pure, _}, _), do: nil

  defp walk_dag({:free, %Stc.Op.Run{task_id: id, module: mod}, cont}, depth) do
    rest = safe_cont(cont, nil, depth - 1)
    node = {:task, id, mod}
    prepend_rest(node, rest)
  end

  defp walk_dag({:free, %Stc.Op.Sequence{programs: progs}, cont}, depth) do
    nodes = Enum.map(progs, &walk_dag(&1, depth - 1)) |> Enum.reject(&is_nil/1)
    rest = safe_cont(cont, List.duplicate(nil, length(progs)), depth - 1)
    prepend_rest({:sequence, nodes}, rest)
  end

  defp walk_dag({:free, %Stc.Op.Parallel{programs: progs}, cont}, depth) do
    nodes = Enum.map(progs, &walk_dag(&1, depth - 1)) |> Enum.reject(&is_nil/1)
    rest = safe_cont(cont, List.duplicate(nil, length(progs)), depth - 1)
    prepend_rest({:parallel, nodes}, rest)
  end

  defp walk_dag({:free, %Stc.Op.Unfold{current_step: step}, _cont}, depth) do
    {:unfold, walk_dag(step, depth - 1)}
  end

  defp walk_dag(_, _), do: {:unknown}

  defp safe_cont(cont, arg, depth) do
    walk_dag(cont.(arg), depth)
  rescue
    _ -> nil
  end

  # Flatten same-kind sequences rather than nesting them.
  defp prepend_rest(node, nil), do: node
  defp prepend_rest({:sequence, a}, {:sequence, b}), do: {:sequence, a ++ b}
  defp prepend_rest(node, rest), do: {:sequence, [node, rest]}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @doc "Returns a short human-readable name for an event struct."
  @spec event_type_name(struct()) :: String.t()
  def event_type_name(%Event.Ready{}), do: "ready"
  def event_type_name(%Event.Started{}), do: "started"
  def event_type_name(%Event.Completed{}), do: "completed"
  def event_type_name(%Event.Failed{}), do: "failed"
  def event_type_name(%Event.Pending{}), do: "pending"
  def event_type_name(%Event.Preempted{}), do: "preempted"
  def event_type_name(%Event.Progress{}), do: "progress"
  def event_type_name(other), do: other.__struct__ |> Module.split() |> List.last() |> String.downcase()

  @doc "Returns a short display string for a task/workflow ID."
  @spec short_id(String.t() | nil) :: String.t()
  def short_id(nil), do: "—"
  def short_id(id) when byte_size(id) <= 12, do: id
  def short_id(id), do: String.slice(id, 0, 8) <> "…"

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_scheduler_state(id) do
    Scheduler.get_state(id)
  rescue
    _ -> nil
  end

  defp stream_all_events(cursor, acc, :all) do
    {:ok, events, new_cursor} = Stc.Event.Store.fetch(cursor, limit: 500)

    if events == [] do
      Enum.reverse(acc)
    else
      stream_all_events(new_cursor, Enum.reverse(events) ++ acc, :all)
    end
  end

  defp stream_all_events(cursor, acc, limit) when is_integer(limit) do
    {:ok, events, new_cursor} = Stc.Event.Store.fetch(cursor, limit: min(limit, 500))
    new_acc = Enum.reverse(events) ++ acc

    cond do
      events == [] -> Enum.take(new_acc, limit)
      length(new_acc) >= limit -> Enum.take(new_acc, limit)
      true -> stream_all_events(new_cursor, new_acc, limit)
    end
  end
end
