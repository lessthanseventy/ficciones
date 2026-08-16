defmodule Aleph.Spawn do
  @moduledoc """
  The cockpit's `s` verb, actuated (tlön component 3, §2d). aleph IS the serving node — it
  runs the funes MCP server and holds the `Tokens` registry — so it mints identity
  **in-process** (`Funes.MCP.Spawn.join/3`, no rpc into another node), then hands the env block
  to the **arbiter** to open the pane. The arbiter (a funes capability) owns the "how to open a
  pane" seam, shared with the switchboard's autonomous cold-thread wake — one home, no drift.

  aleph may import funes (the direction is aleph → funes; only the reverse is banned). The
  harness comes up a briefed citizen: its manos extension reads the FUNES_* env, registers, and
  briefs. The launcher/cwd/robustness live in the arbiter's Tmux backend (`:funes,
  :spawn_launcher`, default `mise exec -- pi`); `pi` is the robust default because it talks to
  aleph's MCP DIRECTLY with the static token — no `funes-cli`, so nothing points at the wrong
  node. The live launch is the eye-test.
  """
  alias Funes.Arbiter
  alias Funes.MCP.Spawn, as: Funes

  @doc """
  Spawn a harness session onto an EXISTING thread: join in-process (mint token + build the env
  block), then ask the arbiter to open a pane running it. Returns `{:ok, pane_ref}`,
  `{:error, {:no_thread, id}}` from the join, or `{:error, :inert}` when no real arbiter is
  wired. `opts` passes through to `join` (`:mandate`, `:engine`).
  """
  def session(thread_id, agent_name, opts \\ []) do
    with {:ok, %{exports: exports}} <- Funes.join(thread_id, agent_name, opts) do
      Arbiter.spawn(exports)
    end
  end
end
