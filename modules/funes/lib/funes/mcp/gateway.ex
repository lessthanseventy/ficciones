defmodule Funes.MCP.Gateway do
  @moduledoc """
  The loopback HTTP gateway in front of the MCP server. One job: route `POST /mint`
  to a fresh-token mint, and forward everything else to the anubis StreamableHTTP
  transport that serves the MCP channel.

  ## Why /mint exists

  A pane's `FUNES_TOKEN` used to be frozen into its env at spawn time. That stranded
  the pane the moment the token model changed or the world secret regenerated — the
  literal-tmux Tlön pane survives an aleph restart, but its frozen token didn't
  survive the 2026-08-16 stateless-HMAC amendment, so the next `register` 401'd as
  "stale or unminted." The fix is structural, not a re-mint patch: **no token is
  frozen.** An adapter mints a fresh token on every connect against the SAME origin
  as its `FUNES_MCP_URL` (so it always hits the right world — aleph's `.dev` world on
  4041, or the always-up service's XDG world on 4040), and identity travels as the
  stable, format-agnostic `(FUNES_THREAD, FUNES_AUTHOR, FUNES_MCP_URL)`.

  `/mint` is the endpoint that makes that possible. It takes `{"thread_id", "agent"}`
  and returns `{"token"}`, minting with THIS node's world secret — the same secret
  that validates the token at `/mcp` — so a token minted here always verifies here.

  ## Trust

  Unauthenticated, by design. This is a single-human loopback machine (§8: how a
  machine authenticates is local configuration), Bandit binds 127.0.0.1 only, and
  the mint is the same operation `bin/funes rpc` already exposes to any local shell.
  Minting a token grants no access by itself — the bearer still has to connect to
  `/mcp` and `register` to bind a session, and `register` supersedes zombies. A
  remote attacker can't reach loopback; a local process already has richer attack
  surface. Authentication here would be theater.
  """
  @behaviour Plug

  import Plug.Conn

  alias Anubis.Server.Transport.StreamableHTTP.Plug, as: AnubisTransport
  alias Funes.MCP.Server, as: McpServer
  alias Funes.MCP.Spawn

  @impl true
  def init(_opts) do
    AnubisTransport.init(server: McpServer)
  end

  @impl true
  def call(conn, anubis_opts) do
    case conn.path_info do
      ["mint"] -> mint(conn)
      _ -> AnubisTransport.call(conn, anubis_opts)
    end
  end

  defp mint(%Plug.Conn{method: "POST"} = conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, %{"thread_id" => thread_id, "agent" => agent}}
         when is_integer(thread_id) and is_binary(agent) <- JSON.decode(body),
         {:ok, token} <- Spawn.mint_for(thread_id, agent) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, JSON.encode!(%{token: token}))
    else
      _ ->
        # Any malformed body, missing/typed-wrong field, or no-such-(thread, agent)
        # is a 400 — the adapter surfaces it, never a frozen-token fallback.
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, JSON.encode!(%{error: "mint failed — malformed body or no such (thread, agent)"}))
        |> halt()
    end
  end

  defp mint(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(405, JSON.encode!(%{error: "POST required"}))
    |> halt()
  end
end
