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
  wrappers that actually mint identity and shell out land in a follow-up.
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
  reach pi's env), then `exec` the profile launcher. Mirrors `Cockpit.spawn_agent_window/3`.
  """
  @spec boot_script(String.t(), String.t()) :: String.t()
  def boot_script(exports, launcher) do
    "export TERM=xterm-256color\n" <> exports <> "\nexec " <> launcher
  end
end
