defmodule Funes.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # PubSub is always up — it is the switchboard's nudge and cheap to run, and the
    # test harness needs it so Channel.post can broadcast. The Repo is started
    # except under :test (the harness owns its lifecycle). The switchboard Server is
    # opt-in (off by default): its presence-gating prerequisite exists (BOTH
    # warmth and engine-credit, see Funes.Switchboard), but the wake only pokes for
    # real once a deployment ALSO sets a non-Inert arbiter — so the dogfood hub
    # (aleph, topology A) flips :start_switchboard on, the prod service stays inert
    # until the service→tmux path is proven (see the tlön design doc). The MCP
    # channel is opt-in the same way: a node that serves agents flips :start_mcp on.
    # The consult mirror is on by default (it only writes DB rows, never pokes a pane, so it
    # is safe where the switchboard is deliberately opt-in) — but the test harness turns it
    # off so the pure maybe_mirror tests don't double-fire.
    children =
      [{Phoenix.PubSub, name: Funes.PubSub}] ++
        maybe(:start_repo, true, Funes.Repo) ++
        maybe(:start_consult_mirror, true, Funes.Consult.Mirror) ++
        maybe(:start_switchboard, false, Funes.Switchboard.Server) ++
        maybe(:start_mcp, false, mcp_children())

    Supervisor.start_link(children, strategy: :one_for_one, name: Funes.Supervisor)
  end

  defp maybe(key, default, children) do
    if Application.get_env(:funes, key, default), do: List.wrap(children), else: []
  end

  # The sovereign channel (pi doc §2a): the token registry, the MCP server, and
  # Bandit serving its plug — LOOPBACK ONLY: a listener on a personal machine
  # binds no further than the machine.
  defp mcp_children do
    [
      # Funes.MCP.Tokens is stateless (signed tokens, no registry) — nothing to supervise.
      {Funes.MCP.Server, transport: :streamable_http},
      # The Gateway routes POST /mint (a fresh-token mint for an adapter's per-connect auth)
      # and forwards everything else to the anubis MCP transport. Loopback only — a personal
      # machine binds no further than 127.0.0.1. See Funes.MCP.Gateway for why /mint exists.
      {Bandit, plug: {Funes.MCP.Gateway, []}, ip: {127, 0, 0, 1}, port: Application.get_env(:funes, :mcp_port, 4040)}
    ]
  end
end
