defmodule Funes.MCP.Spawn do
  @moduledoc """
  The human-arbiter's tool (pi doc §2d). Automated spawn — env-in-`send-keys` from
  `Funes.Arbiter` — is the last slice; until it lands, the human is the arbiter, and
  this is how he hands identity to a pane he spawns by hand.

  Run in the SERVING node's `iex` (the one `mise run funes:serve` started, which holds
  the `Funes.MCP.Tokens` registry and Bandit) — a token minted anywhere else dies with
  its node and 401s. `env/2` opens a thread, staffs an agent, mints the connection's
  token, and prints the `export FUNES_*` block to paste into a fresh pi pane. The pi
  extension (`manos`) reads exactly those four variables at `session_start`.
  """
  alias Funes.Channel
  alias Funes.MCP.Tokens
  alias Funes.Staff

  @doc """
  Open a thread titled `title`, staff it with the agent named `agent_name` (registered
  if new), mint a token bound to that (thread, agent), and print the env block. Returns
  `{:ok, %{thread: t, agent: a, token: tok, exports: string}}`.

  Options for a freshly-registered agent: `:mandate` (default "general"), `:engine`
  (default "local"). An existing agent keeps its own — funes has no vendor in the design
  (§8), so `engine` is just a capability handle, resolved to an endpoint elsewhere.
  """
  def env(title, agent_name, opts \\ []) when is_binary(title) and is_binary(agent_name) do
    {:ok, thread} = Channel.open_thread(%{title: title})
    {:ok, agent} = ensure_agent(agent_name, opts)
    {:ok, _thread} = Staff.assign(thread, agent)
    token = Tokens.mint(thread, agent)

    exports = exports(thread, agent, token)
    IO.puts("\n" <> exports <> "\n")

    {:ok, %{thread: thread, agent: agent, token: token, exports: exports}}
  end

  defp ensure_agent(name, opts) do
    case Staff.agent_by_name(name) do
      nil ->
        Staff.register_agent(%{
          name: name,
          mandate: Keyword.get(opts, :mandate, "general"),
          engine: Keyword.get(opts, :engine, "local")
        })

      agent ->
        {:ok, agent}
    end
  end

  defp exports(thread, agent, token) do
    port = Application.get_env(:funes, :mcp_port, 4040)

    """
    export FUNES_MCP_URL="http://127.0.0.1:#{port}/mcp"
    export FUNES_TOKEN="#{token}"
    export FUNES_THREAD="#{thread.id}"
    export FUNES_AUTHOR="#{agent.name}"\
    """
  end
end
