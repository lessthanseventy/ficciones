defmodule Funes.SwitchboardTest do
  # The switchboard's liveness layer (§10, §5b.2, aleph §6), addressed-delivery
  # model (aleph §2): a message wakes who it is addressed to — the thread's LEAD for
  # a plain post, an @mentioned coworker, or the author of a replied-to message —
  # never the whole room. The DB stays the truth (delivered_at is durable).
  use ExUnit.Case, async: false
  alias Funes.{Channel, Message, Repo, Staff, Switchboard}

  setup do
    Application.put_env(:funes, :arbiter, Funes.Arbiter.Test)
    Application.put_env(:funes, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:funes, :arbiter)
      Application.delete_env(:funes, :test_pid)
    end)

    # A single delete_all over message is FK-safe despite the self-referential
    # reply_to: SQLite checks immediate FKs at statement end, by which point parent
    # and child are both gone.
    Repo.delete_all(Message)
    Repo.delete_all(Funes.Session)
    Repo.delete_all(Funes.Thread)
    Repo.delete_all(Funes.Agent)
    :ok
  end

  # Sandra is the thread's lead (orchestrator); Robert is a coworker on it. Both live.
  defp staffed_thread do
    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})

    {:ok, sandra} =
      Staff.register_agent(%{name: "Sandra", mandate: "orchestrator", engine: "deep"})

    {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "reviewer", engine: "fresh"})
    {:ok, _} = Staff.assign(thread, sandra)

    {:ok, _} =
      Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, workspace_ref: "wSandra"})

    {:ok, _} =
      Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, workspace_ref: "wRobert"})

    %{thread: thread, sandra: sandra, robert: robert}
  end

  describe "addressed delivery — who a message wakes (aleph §2)" do
    test "a plain top-level post wakes ONLY the lead, not the rest of the room" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "how's it going?"})

      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wRobert", _}
    end

    test "the lead's own top-level post wakes no agent — it is a report up to the human" do
      %{thread: thread} = staffed_thread()
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "shipped the fix"})
      Switchboard.deliver(m)

      refute_received {:woke, _, _}
    end

    test "an @mention wakes that coworker, not the lead" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{
          thread_id: thread.id,
          author: "stakeholder",
          body: "@Robert can you check CI?"
        })

      Switchboard.deliver(m)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a reply wakes the author of the message it answers" do
      %{thread: thread} = staffed_thread()
      {:ok, parent} = Channel.post(%{thread_id: thread.id, author: "Robert", body: "CI is red"})
      flush()

      {:ok, reply} =
        Channel.post(%{
          thread_id: thread.id,
          author: "stakeholder",
          body: "thanks — fix it?",
          reply_to: parent.id
        })

      Switchboard.deliver(reply)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a wrong-case @mention still reaches the coworker, not the lead" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hey @robert ping"})

      Switchboard.deliver(m)

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "an @handle that names no agent falls back to the lead (never suppresses it)" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@nobody are we good?"})

      Switchboard.deliver(m)

      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wRobert", _}
    end

    test "an ended session is not woken — @mention a coworker who clocked out" do
      %{thread: thread} = staffed_thread()
      robert_session = Staff.session_for_thread(thread)
      assert robert_session.workspace_ref == "wRobert"
      {:ok, _} = Staff.end_session(robert_session)

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "@Robert you there?"})

      Switchboard.deliver(m)

      refute_received {:woke, "wRobert", _}
    end
  end

  describe "delivered ≠ a file (§5b.3)" do
    test "marks delivered once the addressee was woken" do
      %{thread: thread} = staffed_thread()
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "hi"})
      assert m.delivered_at == nil

      Switchboard.deliver(m)
      assert %DateTime{} = Repo.get!(Message, m.id).delivered_at
    end

    test "a message no live addressee can receive stays undelivered" do
      # A thread with a lead assigned but whose session hasn't started: nobody live
      # to wake, so the post is pending until a session appears and drains it.
      {:ok, thread} = Channel.open_thread(%{title: "unattended"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "lead", engine: "deep"})
      {:ok, _} = Staff.assign(thread, sandra)

      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "anyone?"})
      Switchboard.deliver(m)

      refute_received {:woke, _, _}
      assert Repo.get!(Message, m.id).delivered_at == nil
    end
  end

  describe "drain/0 — durability + coalescing (§10)" do
    test "delivers a backlog posted while nothing was listening" do
      %{thread: thread} = staffed_thread()
      {:ok, m1} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "one"})
      {:ok, m2} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "two"})
      flush()

      Switchboard.drain()

      assert %DateTime{} = Repo.get!(Message, m1.id).delivered_at
      assert %DateTime{} = Repo.get!(Message, m2.id).delivered_at
    end

    test "coalesces a backlog into ONE wake per pane — the burst guard" do
      %{thread: thread} = staffed_thread()

      for body <- ["one", "two", "three"] do
        {:ok, _} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: body})
      end

      flush()
      Switchboard.drain()

      # Three top-level posts all address the lead — Sandra is woken exactly once.
      assert_received {:woke, "wSandra", _}
      refute_received {:woke, "wSandra", _}
    end
  end

  describe "Server — the reactive live path over PubSub" do
    test "a posted message wakes its addressee without anyone calling deliver" do
      %{thread: thread} = staffed_thread()
      start_supervised!(Funes.Switchboard.Server)

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "live!"})

      assert_receive {:woke, "wSandra", _}, 1000
    end

    test "on start it drains a backlog posted while it was down (§10 durability)" do
      %{thread: thread} = staffed_thread()

      {:ok, m} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "left for you"})

      flush()
      assert Repo.get!(Message, m.id).delivered_at == nil

      start_supervised!(Funes.Switchboard.Server)
      assert_receive {:woke, "wSandra", _}, 1000
      assert %DateTime{} = Repo.get!(Message, m.id).delivered_at
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
