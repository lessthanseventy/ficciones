defmodule Funes.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # PubSub is always up — it is the switchboard's nudge and cheap to run, and the
    # test harness needs it so Channel.post can broadcast. The Repo is started
    # except under :test (the harness owns its lifecycle). The switchboard Server is
    # opt-in (off by default) until presence-gating exists — see Funes.Switchboard.
    # The MCP channel is opt-in the same way: tests own its lifecycle, and a node
    # that serves agents flips :start_mcp on.
    children =
      [{Phoenix.PubSub, name: Funes.PubSub}] ++
        maybe(:start_repo, true, Funes.Repo) ++
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
      Funes.MCP.Tokens,
      {Funes.MCP.Server, transport: :streamable_http},
      {Bandit,
       plug: {Anubis.Server.Transport.StreamableHTTP.Plug, server: Funes.MCP.Server},
       ip: {127, 0, 0, 1},
       port: Application.get_env(:funes, :mcp_port, 4040)}
    ]
  end
end
