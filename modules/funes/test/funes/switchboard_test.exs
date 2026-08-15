defmodule Funes.SwitchboardTest do
  # The switchboard's liveness layer (§10, §5b.2, aleph §6). Delivery WAKES the
  # recipient — a post no one is prompted to read is a file. The DB stays the truth
  # (delivered_at is durable); this only decides who to poke and marks the row.
  use ExUnit.Case, async: false
  alias Funes.{Channel, Message, Repo, Staff, Switchboard}

  setup do
    # Capture arbiter wakes in this test's mailbox.
    Application.put_env(:funes, :arbiter, Funes.Arbiter.Test)
    Application.put_env(:funes, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:funes, :arbiter)
      Application.delete_env(:funes, :test_pid)
    end)

    Repo.delete_all(Funes.Session)
    Repo.delete_all(Message)
    Repo.delete_all(Funes.Thread)
    Repo.delete_all(Funes.Agent)
    :ok
  end

  defp staffed_thread do
    {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
    {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "lead", engine: "deep"})
    {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "reviewer", engine: "fresh"})

    {:ok, _} =
      Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, workspace_ref: "wSandra"})

    {:ok, _} =
      Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, workspace_ref: "wRobert"})

    %{thread: thread, sandra: sandra, robert: robert}
  end

  describe "deliver/1 — wake the room" do
    test "wakes the other live sessions on the thread, not the author's own" do
      %{thread: thread} = staffed_thread()

      {:ok, message} =
        Channel.post(%{thread_id: thread.id, author: "Sandra", body: "take a look?"})

      Switchboard.deliver(message)

      # Robert's pane is poked; Sandra (the author) is not woken by her own message.
      assert_received {:woke, "wRobert", _prompt}
      refute_received {:woke, "wSandra", _}
    end

    test "marks the message delivered once a recipient was woken (§5b.3)" do
      %{thread: thread} = staffed_thread()
      {:ok, message} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "hi"})
      assert message.delivered_at == nil

      Switchboard.deliver(message)

      assert %DateTime{} = Repo.get!(Message, message.id).delivered_at
    end

    test "a message with no live recipient stays undelivered — a file, not a delivery" do
      # A thread whose only session is the author's: no one else to wake, so
      # delivered_at stays NULL until a recipient appears and it is drained.
      {:ok, thread} = Channel.open_thread(%{title: "solo"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "lead", engine: "deep"})

      {:ok, _} =
        Staff.start_session(%{
          agent_id: sandra.id,
          thread_id: thread.id,
          workspace_ref: "wSandra"
        })

      {:ok, message} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "anyone?"})

      Switchboard.deliver(message)

      refute_received {:woke, _, _}
      assert Repo.get!(Message, message.id).delivered_at == nil
    end

    test "an ended session is not woken — only live participants are in the room" do
      %{thread: thread} = staffed_thread()
      # Robert clocks out (his session is the newest not-yet-ended on the thread).
      robert_session = Staff.session_for_thread(thread)
      assert robert_session.workspace_ref == "wRobert"
      {:ok, _} = Staff.end_session(robert_session)

      {:ok, message} =
        Channel.post(%{thread_id: thread.id, author: "Sandra", body: "still there?"})

      Switchboard.deliver(message)

      refute_received {:woke, "wRobert", _}
    end
  end

  describe "drain/0 — durability across a dead switchboard (§10)" do
    test "delivers messages posted while nothing was listening — nothing lost" do
      %{thread: thread} = staffed_thread()
      {:ok, m1} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "one"})
      {:ok, m2} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "two"})
      flush()

      Switchboard.drain()

      assert %DateTime{} = Repo.get!(Message, m1.id).delivered_at
      assert %DateTime{} = Repo.get!(Message, m2.id).delivered_at
    end

    test "coalesces a backlog into ONE wake per recipient — the burst guard" do
      # The resumed-conversation fear: N undelivered messages must be one wake, not
      # N. Robert is woken exactly once for the whole backlog; Sandra (who authored
      # all of it) is not woken about her own words.
      %{thread: thread} = staffed_thread()

      for body <- ["one", "two", "three"] do
        {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: body})
      end

      flush()
      Switchboard.drain()

      assert_received {:woke, "wRobert", _}
      refute_received {:woke, "wRobert", _}
      refute_received {:woke, "wSandra", _}
    end

    test "a mixed-author backlog wakes BOTH participants once — each about the other's words" do
      # only_own excludes an agent only if EVERY message is theirs; here both spoke,
      # so both are woken (each has unread from the other), each exactly once.
      %{thread: thread} = staffed_thread()
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "from sandra"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Robert", body: "from robert"})
      flush()

      Switchboard.drain()

      assert_received {:woke, "wSandra", _}
      assert_received {:woke, "wRobert", _}
      refute_received {:woke, _, _}
    end
  end

  describe "Server — the reactive live path over PubSub" do
    test "a posted message wakes the room without anyone calling deliver" do
      %{thread: thread} = staffed_thread()
      # Bring the switchboard up; init subscribes and drains (nothing pending yet).
      start_supervised!(Funes.Switchboard.Server)

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "live!"})

      # The post's broadcast reaches the Server, which wakes Robert — asynchronously,
      # so we wait for it rather than checking the mailbox immediately.
      assert_receive {:woke, "wRobert", _}, 1000
    end

    test "on start it drains a backlog posted while it was down (§10 durability)" do
      %{thread: thread} = staffed_thread()
      # Posted with no Server running: undelivered, no wake yet.
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "left for you"})
      flush()
      assert Repo.get!(Message, m.id).delivered_at == nil

      # The Server comes up and drains on init — the wake was not lost.
      start_supervised!(Funes.Switchboard.Server)
      assert_receive {:woke, "wRobert", _}, 1000
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
