defmodule StcWeb.Dev.Seeds do
  @moduledoc """
  Inserts synthetic STC events and program state for UI development.
  Programs are built with the real Stc.Program DSL so the DAG walker
  can render their structure correctly.

  Run from iex:
      StcWeb.Dev.Seeds.run()
  """

  alias Stc.Event
  alias Stc.Program

  # ---------------------------------------------------------------------------
  # Public
  # ---------------------------------------------------------------------------

  def run do
    seed_sequence_workflow()
    seed_parallel_workflow()
    seed_in_progress_workflow()
    seed_failed_workflow()
    IO.puts("[seeds] done")
  end

  # ---------------------------------------------------------------------------
  # Workflow 1: simple sequence A → B → C, all completed
  # ---------------------------------------------------------------------------

  defp seed_sequence_workflow do
    wf = "wf-seq-#{suffix()}"
    ta = "task-fetch-#{suffix()}"
    tb = "task-transform-#{suffix()}"
    tc = "task-store-#{suffix()}"

    program = Program.sequence([
      Program.run(MyApp.FetchTask,     %{source: "db"},    ta),
      Program.run(MyApp.TransformTask, %{format: "json"},  tb),
      Program.run(MyApp.StoreTask,     %{dest: "s3"},      tc),
    ])

    Stc.Program.Store.put(wf, program)

    t0 = DateTime.utc_now()
    emit_completed(wf, ta, MyApp.FetchTask,     ["agent-1"], t0, 0)
    emit_completed(wf, tb, MyApp.TransformTask, ["agent-1"], t0, 3)
    emit_completed(wf, tc, MyApp.StoreTask,     ["agent-1"], t0, 6)

    IO.puts("[seeds] sequence workflow: #{wf}")
  end

  # ---------------------------------------------------------------------------
  # Workflow 2: parallel fetch then aggregate — parallel([A, B]) → C
  # ---------------------------------------------------------------------------

  defp seed_parallel_workflow do
    wf  = "wf-par-#{suffix()}"
    ta  = "task-fetch-db-#{suffix()}"
    tb  = "task-fetch-api-#{suffix()}"
    tc  = "task-aggregate-#{suffix()}"

    program = Program.sequence([
      Program.parallel([
        Program.run(MyApp.FetchDbTask,  %{table: "users"},      ta),
        Program.run(MyApp.FetchApiTask, %{endpoint: "/events"},  tb),
      ]),
      Program.run(MyApp.AggregateTask, %{strategy: "merge"}, tc),
    ])

    Stc.Program.Store.put(wf, program)

    t0 = DateTime.utc_now()
    # ta and tb start at the same time (parallel)
    emit_completed(wf, ta, MyApp.FetchDbTask,  ["agent-1"], t0, 0)
    emit_completed(wf, tb, MyApp.FetchApiTask, ["agent-2"], t0, 0)
    # tc starts after both finish
    emit_completed(wf, tc, MyApp.AggregateTask, ["agent-1"], t0, 4)

    IO.puts("[seeds] parallel workflow: #{wf}")
  end

  # ---------------------------------------------------------------------------
  # Workflow 3: in-progress — first task done, second running, rest pending
  # ---------------------------------------------------------------------------

  defp seed_in_progress_workflow do
    wf = "wf-live-#{suffix()}"
    ta = "task-init-#{suffix()}"
    tb = "task-process-#{suffix()}"
    tc = "task-notify-#{suffix()}"

    program = Program.sequence([
      Program.run(MyApp.InitTask,    %{}, ta),
      Program.run(MyApp.ProcessTask, %{batch: 100}, tb),
      Program.run(MyApp.NotifyTask,  %{channel: "slack"}, tc),
    ])

    Stc.Program.Store.put(wf, program)

    t0 = DateTime.utc_now()
    emit_completed(wf, ta, MyApp.InitTask,    ["agent-1"], t0, 0)
    emit_started(  wf, tb, MyApp.ProcessTask, ["agent-1"], t0, 3)
    # tc has no events yet — still pending in program

    IO.puts("[seeds] in-progress workflow: #{wf}")
  end

  # ---------------------------------------------------------------------------
  # Workflow 4: failed with retry — task B failed once, retried and completed
  # ---------------------------------------------------------------------------

  defp seed_failed_workflow do
    wf = "wf-retry-#{suffix()}"
    ta = "task-validate-#{suffix()}"
    tb = "task-upload-#{suffix()}"

    program = Program.sequence([
      Program.run(MyApp.ValidateTask, %{schema: "v2"}, ta),
      Program.run(MyApp.UploadTask,   %{bucket: "prod"}, tb),
    ])

    Stc.Program.Store.put(wf, program)

    t0 = DateTime.utc_now()
    emit_completed(wf, ta, MyApp.ValidateTask, ["agent-1"], t0, 0)

    # tb: first attempt fails, second succeeds
    emit_ready(  wf, tb, MyApp.UploadTask, t0, 3)
    emit_started(wf, tb, MyApp.UploadTask, ["agent-1"], t0, 4)
    append(%Event.Failed{
      workflow_id: wf,
      task_id: tb,
      agent_ids: ["agent-1"],
      reason: :connection_timeout,
      retriable: true,
      attempt: 1,
      timestamp: offset(t0, 6)
    })
    emit_ready(  wf, tb, MyApp.UploadTask, t0, 7)
    emit_started(wf, tb, MyApp.UploadTask, ["agent-2"], t0, 8)
    append(%Event.Completed{
      workflow_id: wf,
      task_id: tb,
      agent_ids: ["agent-2"],
      result: {:ok, "uploaded"},
      attempt: 2,
      timestamp: offset(t0, 10)
    })

    IO.puts("[seeds] retry workflow: #{wf}")
  end

  # ---------------------------------------------------------------------------
  # Event helpers
  # ---------------------------------------------------------------------------

  defp emit_completed(wf, task_id, mod, agents, t0, secs) do
    emit_ready(wf, task_id, mod, t0, secs)
    emit_started(wf, task_id, mod, agents, t0, secs + 1)
    append(%Event.Completed{
      workflow_id: wf,
      task_id: task_id,
      agent_ids: agents,
      result: {:ok, :done},
      attempt: 1,
      timestamp: offset(t0, secs + 2)
    })
  end

  defp emit_started(wf, task_id, _mod, agents, t0, secs) do
    append(%Event.Started{
      workflow_id: wf,
      task_id: task_id,
      agent_ids: agents,
      timestamp: offset(t0, secs)
    })
  end

  defp emit_ready(wf, task_id, mod, t0, secs) do
    append(%Event.Ready{
      workflow_id: wf,
      task_id: task_id,
      module: mod,
      payload: %{},
      timestamp: offset(t0, secs)
    })
  end

  defp append(event) do
    Stc.Event.Store.append(event)
    :timer.sleep(2)
  end

  defp offset(t0, secs), do: DateTime.add(t0, secs, :second)
  defp suffix, do: :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
end
