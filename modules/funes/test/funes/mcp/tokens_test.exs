defmodule Funes.MCP.TokensTest do
  # The identity seam (pi doc §2a): a token minted IN the funes node binds an MCP
  # connection to its (thread, agent) — identity is a property of the connection,
  # never a parameter of a call, so cross-thread misdirection is unrepresentable.
  # Tokens are ephemeral by design: they live in the node, and a restart
  # invalidates them — an honest failure the agent surfaces, never a stale grant.
  use ExUnit.Case, async: false
  alias Funes.{Channel, MCP, Staff}

  setup do
    Funes.TestDB.clean!()
    start_supervised!(MCP.Tokens)
    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
    {:ok, agent} = Staff.register_agent(%{name: "Carl", mandate: "m", engine: "e"})
    %{thread: thread, agent: agent}
  end

  test "mint/2 → resolve/1 round-trips the binding", %{thread: thread, agent: agent} do
    token = MCP.Tokens.mint(thread, agent)

    assert {:ok, binding} = MCP.Tokens.resolve(token)
    assert binding.thread_id == thread.id
    assert binding.agent_id == agent.id
    assert binding.agent == "Carl"
    # No session until register claims one — nil is honest, never a placeholder.
    assert binding.session_id == nil
  end

  test "an unknown token resolves to :error" do
    assert MCP.Tokens.resolve("no-such-token") == :error
  end

  test "two mints yield distinct tokens", %{thread: thread, agent: agent} do
    assert MCP.Tokens.mint(thread, agent) != MCP.Tokens.mint(thread, agent)
  end

  test "bind_session/2 attaches the registered session to later resolves", %{
    thread: thread,
    agent: agent
  } do
    token = MCP.Tokens.mint(thread, agent)

    {:ok, session} =
      Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})

    :ok = MCP.Tokens.bind_session(token, session.id)

    assert {:ok, %{session_id: session_id}} = MCP.Tokens.resolve(token)
    assert session_id == session.id
  end

  test "bind_session/2 on an unknown token is refused" do
    assert MCP.Tokens.bind_session("no-such-token", 1) == :error
  end
end
