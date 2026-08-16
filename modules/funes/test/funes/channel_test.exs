defmodule Funes.ChannelTest do
  # Step 2: the thread + message spine (aleph §9.2, spec §5b). The thread is the
  # atom of work; the message is the channel and §4's capture path — a message a
  # participant writes is already a durable row. The DB is the bus (§10): every
  # assertion here reads back through SQLite, never through in-memory state.
  use ExUnit.Case, async: false

  alias Funes.Channel
  alias Funes.Message
  alias Funes.Repo
  alias Funes.Thread

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  describe "open_thread/1" do
    test "opens a thread that reads back as a durable, open row" do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})

      # Read it back from SQLite, not from the struct we were handed — the row is
      # the truth, the struct is a copy.
      reloaded = Repo.get!(Thread, thread.id)
      assert reloaded.title == "review PR 329"
      assert reloaded.state == "open"
      assert %DateTime{} = reloaded.created_at
    end
  end

  describe "post/1 — the capture path" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      %{thread: thread}
    end

    test "a posted message is immediately a durable row (§4/§5b capture path)", %{thread: thread} do
      {:ok, message} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "look at this"})

      # The row must exist in SQLite, not just in the struct we hold — §10, the DB
      # is the bus. Re-read it.
      reloaded = Repo.get!(Message, message.id)
      assert reloaded.thread_id == thread.id
      assert reloaded.author == "stakeholder"
      assert reloaded.body == "look at this"
      assert %DateTime{} = reloaded.created_at
    end

    test "a thread and a body are the only required fields (§5b)", %{thread: thread} do
      # Missing body.
      assert {:error, changeset} = Channel.post(%{thread_id: thread.id, author: "sandra"})
      assert %{body: _} = errors_on(changeset)

      # Missing author (a message has a speaker).
      assert {:error, changeset} = Channel.post(%{thread_id: thread.id, body: "hi"})
      assert %{author: _} = errors_on(changeset)

      # Missing thread — a message with no thread is meaningless.
      assert {:error, changeset} = Channel.post(%{author: "sandra", body: "hi"})
      assert %{thread_id: _} = errors_on(changeset)
    end

    test "a message cannot reference a thread that does not exist — SQLite itself refuses it" do
      # The FK is the DB's own guard (§10): not a mirrored app-side check that
      # could race or go stale. An orphan write is refused by SQLite, so it raises
      # rather than returning a tidy changeset — proving the enforcement is real.
      assert_raise Ecto.ConstraintError, fn ->
        Channel.post(%{thread_id: 999_999, author: "sandra", body: "ghost"})
      end
    end
  end

  describe "delivered ≠ read (§5b.3)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      {:ok, message} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "hi"})
      %{message: message}
    end

    test "a freshly posted message is undelivered — the sender cannot assert delivery", %{
      message: message
    } do
      assert message.delivered_at == nil
      assert Repo.get!(Message, message.id).delivered_at == nil
    end

    test "a sender cannot fake delivery by smuggling delivered_at through post/1" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})

      {:ok, message} =
        Channel.post(%{
          thread_id: thread.id,
          author: "sandra",
          body: "trust me it's read",
          delivered_at: ~U[2020-01-01 00:00:00Z]
        })

      # The forged stamp is ignored: post/1 does not cast delivered_at at all.
      assert Repo.get!(Message, message.id).delivered_at == nil
    end

    # Delivery-stamping is the switchboard's atomic claim, tested in
    # Funes.SwitchboardTest ("marks delivered once the addressee was woken"). The
    # channel's own contract here is only that a sender cannot assert it.

    test "there is no `read` column — nothing can prove a read, so it does not exist" do
      # §5b.3: a column that could only ever lie must not exist. Assert the schema
      # has no field that would tempt a sender-written 'read' receipt.
      refute :read in Message.__schema__(:fields)
      refute :read_at in Message.__schema__(:fields)
    end
  end

  describe "reading a thread" do
    test "messages come back in the order they were posted" do
      {:ok, thread} = Channel.open_thread(%{title: "an argument"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "first"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "robert", body: "second"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "third"})

      bodies = thread |> Channel.thread_messages() |> Enum.map(& &1.body)
      assert bodies == ["first", "second", "third"]
    end

    test "a thread's messages are scoped to it, not another thread's" do
      {:ok, t1} = Channel.open_thread(%{title: "one"})
      {:ok, t2} = Channel.open_thread(%{title: "two"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "a", body: "mine"})
      {:ok, _} = Channel.post(%{thread_id: t2.id, author: "b", body: "theirs"})

      assert t1 |> Channel.thread_messages() |> Enum.map(& &1.body) == ["mine"]
    end

    test "open_threads/0 returns open threads and omits closed ones" do
      {:ok, open} = Channel.open_thread(%{title: "still open"})
      {:ok, done} = Channel.open_thread(%{title: "finished"})
      {:ok, _} = Channel.close_thread(done)

      titles = Enum.map(Channel.open_threads(), & &1.title)
      assert open.title in titles
      refute done.title in titles
    end

    test "recent_across/1 — the Comms chorus feed: messages from every thread, each tagged" do
      {:ok, t1} = Channel.open_thread(%{title: "fable review"})
      {:ok, t2} = Channel.open_thread(%{title: "triage inbox"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "andrew", body: "start it"})
      {:ok, _} = Channel.post(%{thread_id: t2.id, author: "Carl", body: "CI is red"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "pi", body: "on it"})

      feed = Channel.recent_across(50)
      # chat order, newest at the bottom, drawn from BOTH threads with the thread title carried
      assert Enum.map(feed, & &1.body) == ["start it", "CI is red", "on it"]
      assert Enum.map(feed, & &1.thread_title) == ["fable review", "triage inbox", "fable review"]
    end

    test "recent_across/1 caps to the newest `limit`, still oldest-first" do
      {:ok, t} = Channel.open_thread(%{title: "chatty"})
      for i <- 1..5, do: Channel.post(%{thread_id: t.id, author: "a", body: "m#{i}"})

      feed = Channel.recent_across(3)
      # the 3 NEWEST (m3,m4,m5), returned oldest-first
      assert Enum.map(feed, & &1.body) == ["m3", "m4", "m5"]
    end
  end

  describe "the state CHECK is the DB's own guard" do
    test "a thread state outside the closed set is refused by SQLite itself" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})

      # No app-side validate_inclusion mirrors this (§2, single source of truth):
      # the closed set lives in the DB CHECK, so a bad state is refused there and
      # raises, exactly as an orphan FK does.
      assert_raise Ecto.ConstraintError, fn ->
        thread |> Thread.state_changeset("garbage") |> Repo.update()
      end
    end
  end

  describe "close_thread/1" do
    test "closes a thread but keeps its messages — history is never taken down with it" do
      {:ok, thread} = Channel.open_thread(%{title: "wrap it up"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "done"})

      {:ok, closed} = Channel.close_thread(thread)
      assert closed.state == "closed"
      assert Repo.get!(Thread, thread.id).state == "closed"

      # The messages survive the close.
      assert thread |> Channel.thread_messages() |> Enum.map(& &1.body) == ["done"]
    end
  end

  describe "message/1" do
    test "returns the message row, or nil — the from_message hook for stated facts" do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, posted} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "verbatim"})

      assert %Message{body: "verbatim"} = Channel.message(posted.id)
      assert Channel.message(999_999) == nil
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
