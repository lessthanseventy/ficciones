defmodule Aleph.Crew do
  @moduledoc """
  The funes crew — roles the leader spawns onto a task thread and tears down when done.

  A **role** is a seat, not an identity: a `%{handle, window_prefix, profile}` naming the funes
  author the seat posts as, the tmux window it runs in, and the `Aleph.Profile` that materialises
  its pi config. MVP staffs one role, `reviewer`.

  The per-thread window name (`crew_window/2`) is a PURE function of (role, thread id), so the
  spawner (the `mix aleph.crew.*` task, in its own BEAM) and the mention router (in the cockpit
  BEAM) agree on `r<tid>` with no shared state — that is what lets a leader-invoked CLI spawn a
  window the running cockpit can route `@reviewer-machine` to.

  Pure tmux command builders (`spawn_argv/3`, `kill_argv/2`, `boot_script/2`) live below; the IO
  wrappers (`spawn/4`, `kill/2`) mint identity, materialise the profile, shell out to tmux, and
  inject the leader's opening turn. The command runner and identity minter are injected via app env
  (`:aleph, :crew_cmd` / `:crew_join`) so the seam tests headless, same pattern as the cockpit's
  `:spawn_launcher`.
  """

  alias Aleph.Profiles
  alias Aleph.Space

  @tlon_session "tlon"

  @roles %{
    "reviewer" => %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"}
  }

  @doc "The MVP crew: role key → %{handle, window_prefix, profile}."
  @spec roles() :: %{String.t() => map()}
  def roles, do: @roles

  @doc "A role by key, or nil."
  @spec role(String.t()) :: map() | nil
  def role(key), do: Map.get(@roles, key)

  @doc "The funes handle → role key (reverse of `role/1`'s handle), or nil for a non-crew handle."
  @spec handle_role(String.t()) :: String.t() | nil
  def handle_role(handle) do
    Enum.find_value(@roles, fn {key, %{handle: h}} -> if h == handle, do: key end)
  end

  @doc """
  The tmux window a role runs in on a given thread: `<prefix><thread_id>` (e.g. `"r42"`). Pure and
  deterministic — the spawner and the router both compute it. Raises on an unknown role.
  """
  @spec crew_window(String.t(), integer() | String.t()) :: String.t()
  def crew_window(role_key, thread_id) do
    case role(role_key) do
      %{window_prefix: p} -> p <> to_string(thread_id)
      nil -> raise ArgumentError, "unknown crew role: #{inspect(role_key)}"
    end
  end

  @doc "The tmux server socket the Tlön coworkers share (`aleph-<tlon coworker>`), e.g. `aleph-tertius`."
  @spec tlon_socket() :: String.t()
  def tlon_socket, do: Profiles.socket(Space.fetch(:tlon).coworker)

  @doc "The `tmux` argv to spawn a role's per-thread window (detached) running `script`."
  @spec spawn_argv(String.t(), integer() | String.t(), String.t()) :: [String.t()]
  def spawn_argv(role_key, thread_id, script) do
    [
      "-L",
      tlon_socket(),
      "new-window",
      "-d",
      "-t",
      @tlon_session,
      "-n",
      crew_window(role_key, thread_id),
      script
    ]
  end

  @doc "The `tmux` argv to tear down a role's per-thread window."
  @spec kill_argv(String.t(), integer() | String.t()) :: [String.t()]
  def kill_argv(role_key, thread_id) do
    ["-L", tlon_socket(), "kill-window", "-t", "#{@tlon_session}:#{crew_window(role_key, thread_id)}"]
  end

  @doc """
  The window's boot script: set TERM, source the funes `exports` block (so `${FUNES_MCP_URL}` etc.
  reach pi's env), then `exec` the bare pi launcher. Mirrors `Cockpit.spawn_agent_window/3` — a
  role's window rides the ALREADY-created `r<tid>` window on the shared tlon server, so it must
  exec the bare `Cockpit.pi_command/1`, never `profile_launcher/1` (a `tmux new-session` wrapper
  meant for a coworker's own dedicated server — execing it here would nest a second server).
  """
  @spec boot_script(String.t(), String.t()) :: String.t()
  def boot_script(exports, launcher) do
    "export TERM=xterm-256color\n" <> exports <> "\nexec " <> launcher
  end

  # The reviewer runs on the SAME funes the cockpit uses (aleph's :4041/.dev) — the injected minter
  # defaults to Funes.MCP.Spawn.join, which reads :funes/:mcp_port from the running app config, so a
  # `mix aleph.crew.*` task inherits aleph's funes port/db just by booting the aleph app.
  defp cmd_runner, do: Application.get_env(:aleph, :crew_cmd, &System.cmd/3)
  defp joiner, do: Application.get_env(:aleph, :crew_join, &Funes.MCP.Spawn.join/3)

  # Wait between window boot and injecting the opening turn — the profile pi's TUI must settle before
  # send-keys, same reason as Cockpit's @opening_submit_delay_ms two-phase inject. Overridable via app
  # env (`:aleph, :crew_settle_ms`) so tests don't pay the real delay.
  @opening_settle_ms 1_500
  defp opening_settle_ms, do: Application.get_env(:aleph, :crew_settle_ms, @opening_settle_ms)

  @doc """
  Spawn `role_key` onto task `thread_id` as a funes citizen, then inject the leader's `task` as its
  opening turn. Returns `{:ok, window}`. `opts[:inject]` (default true) can be set false in tests to
  skip the timed send-keys.
  """
  @spec spawn(String.t(), integer() | String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def spawn(role_key, thread_id, task, opts \\ []) do
    with %{handle: handle, profile: profile_name} <- role(role_key) || :unknown_role,
         %Aleph.Profile{} = profile <- Profiles.fetch(profile_name) || {:missing_profile, profile_name},
         _dir = Profiles.materialise!(profile),
         {:ok, %{exports: exports}} <- joiner().(thread_id, handle, mandate: "machine", assign: false),
         script = boot_script(exports, Aleph.Cockpit.pi_command(profile)),
         {:ok, window} <- run_spawn(role_key, thread_id, script) do
      if Keyword.get(opts, :inject, true), do: inject_opening(window, opening_turn(thread_id, task))
      {:ok, window}
    else
      :unknown_role -> {:error, {:unknown_role, role_key}}
      {:missing_profile, _} = err -> {:error, err}
      {:error, _} = err -> err
      other -> {:error, other}
    end
  end

  # Shells out to tmux and folds its exit status into a tagged result — `spawn/4`'s @spec promises
  # `{:error, term()}`, never a crash, so a duplicate window (very plausible re-spawning onto the
  # same thread) or any other nonzero exit must not raise a MatchError.
  defp run_spawn(role_key, thread_id, script) do
    case cmd_runner().("tmux", spawn_argv(role_key, thread_id, script), stderr_to_stdout: true) do
      {_out, 0} -> {:ok, crew_window(role_key, thread_id)}
      {out, _status} -> {:error, {:tmux_failed, out}}
    end
  end

  @doc "Tear down a role's window on a thread. Best-effort; a missing window is not an error."
  @spec kill(String.t(), integer() | String.t()) :: :ok
  def kill(role_key, thread_id) do
    _ = cmd_runner().("tmux", kill_argv(role_key, thread_id), stderr_to_stdout: true)
    :ok
  end

  # The opening assignment the leader hands the reviewer. Names the leader handle so the reviewer's
  # @<leader> ESCALATE resolves — MVP leader is claude-machine (the task thread's staffed lead).
  defp opening_turn(thread_id, task) do
    "You are reviewing on funes thread ##{thread_id}. Leader handle: claude-machine. " <>
      "Task: #{task}. Read the diff (git diff/show), post findings, and escalate any fix per your protocol."
  end

  # Two-phase send-keys into the freshly-booted window: literal text, settle, then Enter. Best-effort.
  defp inject_opening(window, text) do
    sock = tlon_socket()
    target = "#{@tlon_session}:#{window}"
    _ = cmd_runner().("tmux", ["-L", sock, "send-keys", "-l", "-t", target, text], stderr_to_stdout: true)
    Process.sleep(opening_settle_ms())
    _ = cmd_runner().("tmux", ["-L", sock, "send-keys", "-t", target, "Enter"], stderr_to_stdout: true)
    :ok
  end
end
