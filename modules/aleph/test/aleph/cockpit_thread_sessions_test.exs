defmodule Aleph.CockpitThreadSessionsTest do
  @moduledoc """
  Per-thread leaf sessions (per-thread-agents Slice A): `ensure_thread_sessions/2` spawns a
  dedicated window for EVERY worker-archetype lead — claude AND pi harness — dispatched by the
  lead's roster profile, through the same `:tlon_cmd`/`:tlon_join` seams as
  `Aleph.CockpitRosterTest`. A meta (surveyor) lead never gets a leaf window: it is the vantage,
  not a worker. Boots its own temp DB (staffed threads are a real Repo read), so not async.
  """
  use ExUnit.Case, async: false

  alias Aleph.Cockpit
  alias Aleph.Space
  alias Ecto.Adapters.SQLite3
  alias Funes.Channel
  alias Funes.Repo
  alias Funes.Staff

  @worlds [
    %{
      id: 99,
      name: "Freedonia",
      roster: [
        %{"archetype" => "surveyor", "name" => "rufus"},
        %{"archetype" => "builder", "name" => "hronir"},
        %{"archetype" => "planner", "name" => "borges"}
      ]
    }
  ]

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_thread_sessions_test_#{System.unique_integer([:positive])}.db")
    Application.put_env(:funes, Repo, Keyword.merge(Application.get_env(:funes, Repo, []), database: db, pool_size: 1))

    config = Repo.config()
    _ = SQLite3.storage_down(config)
    :ok = SQLite3.storage_up(config)
    {:ok, _repo} = Repo.start_link()
    Ecto.Migrator.run(Repo, :up, all: true)

    for handle <- ["rufus-machine", "hronir-machine", "borges-machine"] do
      {:ok, _} = Staff.register_agent(%{name: handle, mandate: "machine", engine: "test"})
    end

    on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = SQLite3.storage_down(config)
    end)

    :ok
  end

  setup do
    test_pid = self()

    # spawn_pi_window materialises the lead's profile config dir — point the pi root at a tmp dir
    # so the suite never writes the real ~/.pi.
    pi_root = Path.join(System.tmp_dir!(), "aleph_thread_sessions_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))

    Application.put_env(:aleph, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      if Enum.member?(args, "list-windows"), do: {"1\t0\trufus\n", 0}, else: {"", 0}
    end)

    Application.put_env(:aleph, :tlon_join, fn thread_id, agent, opts ->
      send(test_pid, {:join, thread_id, agent, opts})
      {:ok, %{exports: ~s(export FUNES_THREAD="#{thread_id}"\nexport FUNES_AUTHOR="#{agent}")}}
    end)

    # Each test stages its own thread — clear the previous test's so a stale staffed thread can't
    # produce an extra spawn the refute_receive assertions would trip on.
    {:ok, _} = Channel.clear_machine_threads()

    on_exit(fn ->
      Application.delete_env(:aleph, :tlon_cmd)
      Application.delete_env(:aleph, :tlon_join)
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      File.rm_rf!(pi_root)
    end)

    :ok
  end

  defp staffed_thread(handle) do
    {:ok, thread} = Channel.open_thread(%{title: "task for #{handle}", scope: "machine"})
    {:ok, _} = Channel.assign_lead(thread.id, handle)
    thread
  end

  defp state,
    do: %{
      active_key: 99,
      standing_thread_id: nil,
      thread_spawn_retry: %{},
      opening_injected: MapSet.new(),
      opening_text_at: %{}
    }

  test "a pi-harness worker lead gets its own leaf window (the Slice A isolation fix)" do
    # Slice D: the WORK environment binds the (anthropic-model) planner to pi; at home it would
    # ride claude_code like every anthropic archetype.
    System.put_env("ALEPH_ENV", "work")
    on_exit(fn -> System.delete_env("ALEPH_ENV") end)

    thread = staffed_thread("borges-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@worlds))

    assert_receive {:join, tid, "borges-machine", opts}
    assert tid == thread.id
    assert opts[:mandate] == "machine"

    # Slice C: a HUMAN window name (`<archetype>-<title-slug>`), not `t<id>` …
    window = "planner-task-for-borges-machine"
    assert_receive {:tmux, ["-L", "aleph-world-99", "new-window", "-d", "-t", "w99", "-n", ^window, script]}
    assert script =~ "PI_CODING_AGENT_DIR"
    refute script =~ "modules/manos/claude-code/launch.sh"

    # … with the thread id stamped as the `@funes_thread` routing key, so nothing parses the name.
    thread_tag = "#{thread.id}"
    target = "w99:=" <> window

    assert_receive {:tmux, ["-L", "aleph-world-99", "set-option", "-w", "-t", ^target, "@funes_thread", ^thread_tag]}
  end

  test "a claude-harness worker lead still gets its claude leaf window (regression)" do
    thread = staffed_thread("hronir-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@worlds))

    assert_receive {:join, _tid, "hronir-machine", _opts}

    window = "builder-task-for-hronir-machine"
    assert_receive {:tmux, ["-L", "aleph-world-99", "new-window", "-d", "-t", "w99", "-n", ^window, script]}
    assert script =~ "modules/manos/claude-code/launch.sh"
    refute script =~ "PI_CODING_AGENT_DIR"

    thread_tag = "#{thread.id}"
    target = "w99:=" <> window

    assert_receive {:tmux, ["-L", "aleph-world-99", "set-option", "-w", "-t", ^target, "@funes_thread", ^thread_tag]}
  end

  test "a live `@funes_thread`-tagged window suppresses a respawn — the routing map, not the name, is the identity" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    Application.put_env(:aleph, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\n0\t1\tanything-at-all\t#{thread.id}\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@worlds))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end

  test "a meta (surveyor) lead never gets a leaf window — the vantage is not a worker" do
    staffed_thread("rufus-machine")

    Cockpit.ensure_thread_sessions(state(), Space.all(@worlds))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end

  test "an orphan leaf window (thread closed/cleared while aleph was down) is swept" do
    thread = staffed_thread("borges-machine")
    test_pid = self()

    # One live tagged leaf (kept), one tagged for a vanished thread, one legacy t<id> orphan —
    # and the untagged center/tail windows, which are never sweep candidates.
    Application.put_env(:aleph, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\trufus\t\n0\t1\tplanner-live\t#{thread.id}\n0\t2\treviewer-stale\t999888\n0\t3\tt777666\t\n", 0},
        else: {"", 0}
    end)

    Cockpit.ensure_thread_sessions(state(), Space.all(@worlds))

    assert_receive {:tmux, ["-L", "aleph-world-99", "kill-window", "-t", "w99:2"]}
    assert_receive {:tmux, ["-L", "aleph-world-99", "kill-window", "-t", "w99:3"]}
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", "w99:0"]}, 20
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", "w99:1"]}, 20
  end

  test "the standing thread is excluded — the center already runs it" do
    thread = staffed_thread("borges-machine")

    Cockpit.ensure_thread_sessions(%{state() | standing_thread_id: thread.id}, Space.all(@worlds))

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end
end
