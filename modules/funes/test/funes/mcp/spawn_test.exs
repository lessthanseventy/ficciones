defmodule Funes.MCP.SpawnTest do
  # The spawn-or-join primitive under the launchers (funes:spawn / funes:claude /
  # pi:*). `ensure` is the shared core — open a fresh thread or join an existing one,
  # staff the agent — with NO token. `env`/`join` add the mint + the export block (the
  # pi/human path, a static bearer). `mint_for` is the Claude-Code `headersHelper` path:
  # a fresh token for an EXISTING (thread, agent), on every connect.
  use ExUnit.Case, async: false

  alias Funes.Channel
  alias Funes.MCP.Spawn
  alias Funes.MCP.Tokens
  alias Funes.Repo
  alias Funes.Staff
  alias Funes.Thread

  setup do
    Funes.TestDB.clean!()
    start_supervised!(Tokens)
    :ok
  end

  describe "ensure/3 — spawn or join, no token" do
    test "{:open, title} opens a thread and staffs a freshly-registered agent" do
      assert {:ok, %{thread: t, agent: a} = result} = Spawn.ensure({:open, "new work"}, "codex")
      assert t.title == "new work"
      assert a.name == "codex"
      assert Repo.get(Thread, t.id).agent_id == a.id
      # the core mints nothing — exactly the two keys
      assert result |> Map.keys() |> Enum.sort() == [:agent, :thread]
    end

    test "{:join, id} joins an existing thread and assigns the agent" do
      {:ok, existing} = Channel.open_thread(%{title: "existing"})
      assert {:ok, %{thread: t, agent: a}} = Spawn.ensure({:join, existing.id}, "kimi")
      assert t.id == existing.id
      assert Repo.get(Thread, existing.id).agent_id == a.id
    end

    test "{:join, missing} errors, never silently opens a new thread" do
      assert {:error, {:no_thread, 999_999}} = Spawn.ensure({:join, 999_999}, "kimi")
    end

    test "reuses an existing agent by name (no duplicate registration)" do
      {:ok, agent} = Staff.register_agent(%{name: "dup", mandate: "m", engine: "e"})
      assert {:ok, %{agent: a}} = Spawn.ensure({:open, "t"}, "dup")
      assert a.id == agent.id
    end
  end

  describe "env/3 and join/3 — mint + exports" do
    test "env/3 opens, mints, returns a valid token and the four-var export block" do
      assert {:ok, %{thread: t, token: tok, exports: ex}} = Spawn.env("fresh", "codex")
      assert is_binary(tok)
      assert ex =~ ~s(FUNES_TOKEN="#{tok}")
      assert ex =~ ~s(FUNES_THREAD="#{t.id}")
      assert ex =~ ~s(FUNES_AUTHOR="codex")
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "join/3 joins an existing thread and mints a token bound to it" do
      {:ok, existing} = Channel.open_thread(%{title: "join me"})
      assert {:ok, %{thread: t, token: tok, exports: ex}} = Spawn.join(existing.id, "codex")
      assert t.id == existing.id
      assert ex =~ ~s(FUNES_THREAD="#{existing.id}")
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "join/3 errors on a missing thread" do
      assert {:error, {:no_thread, 999_999}} = Spawn.join(999_999, "codex")
    end
  end

  describe "mint_for/2 — a fresh token for an EXISTING (thread, agent)" do
    test "mints for an existing thread + agent (the headersHelper path)" do
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh"}, "claude-code")
      assert {:ok, tok} = Spawn.mint_for(t.id, "claude-code")
      assert {:ok, _binding} = Tokens.resolve(tok)
    end

    test "a second mint_for yields a DIFFERENT token (fresh per connect)" do
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh"}, "claude-code")
      {:ok, first} = Spawn.mint_for(t.id, "claude-code")
      {:ok, second} = Spawn.mint_for(t.id, "claude-code")
      assert first != second
    end

    test "errors on a missing thread or agent" do
      {:ok, %{thread: t}} = Spawn.ensure({:open, "hh2"}, "claude-code")
      assert {:error, {:no_thread, 999_999}} = Spawn.mint_for(999_999, "claude-code")
      assert {:error, {:no_agent, "ghost"}} = Spawn.mint_for(t.id, "ghost")
    end
  end
end
