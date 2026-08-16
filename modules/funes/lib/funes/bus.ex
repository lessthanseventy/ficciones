defmodule Funes.Bus do
  @moduledoc """
  The reactive substrate over the durable bus (aleph §5). `Phoenix.PubSub` fans
  **typed events** out to **focused topics**, so a consumer subscribes to exactly
  what it needs — the switchboard to the message firehose, the board to one thread
  (IN SCOPE) or the roster (IN FLIGHT) — instead of filtering everything.

  This is *liveness only*: every event is already a durable row before it is
  broadcast, and a broadcast with no subscriber is a harmless no-op. Kill PubSub and
  nothing is lost; readers recover from the DB.

  ## Topics
    * `funes:messages`      — every posted message (the switchboard's stream)
    * `funes:thread:{id}`   — everything on one thread: messages, facts, events,
                              issues, assignment/close (feeds IN SCOPE)
    * `funes:threads`       — thread lifecycle: opened, closed, assigned (the list)
    * `funes:sessions`      — session start/end (feeds the IN FLIGHT roster)

  ## Events (the envelope every subscriber matches)
    `{:message_posted, message}` · `{:fact_banked, fact}` · `{:event_recorded, event}`
    `{:issue_raised, issue}` · `{:issue_resolved, issue}` · `{:thread_opened, thread}`
    `{:thread_closed, thread}` · `{:thread_assigned, thread}` · `{:session_started, s}`
    `{:session_ended, s}`
  """
  @pubsub Funes.PubSub

  # --- topics ---
  def messages_topic, do: "funes:messages"
  def thread_topic(id), do: "funes:thread:#{id}"
  def threads_topic, do: "funes:threads"
  def sessions_topic, do: "funes:sessions"

  # --- subscribe ---
  def subscribe_messages, do: sub(messages_topic())
  def subscribe_thread(id), do: sub(thread_topic(id))
  def subscribe_threads, do: sub(threads_topic())
  def subscribe_sessions, do: sub(sessions_topic())

  # --- unsubscribe (a consumer that follows the *focused* thread drops the old topic on a switch) ---
  def unsubscribe_thread(id), do: Phoenix.PubSub.unsubscribe(@pubsub, thread_topic(id))

  defp sub(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  @doc """
  Broadcast a typed event to the topic(s) it belongs on. Routing is centralized here
  so the topic scheme has one home. Returns `:ok`.
  """
  def broadcast({:message_posted, m} = event) do
    publish([messages_topic() | thread_topics(m.thread_id)], event)
  end

  def broadcast({tag, %{thread_id: thread_id} = _row} = event)
      when tag in [:fact_banked, :event_recorded, :issue_raised, :issue_resolved] do
    publish(thread_topics(thread_id), event)
  end

  def broadcast({tag, thread} = event)
      when tag in [:thread_opened, :thread_closed, :thread_assigned] do
    publish([threads_topic() | thread_topics(thread.id)], event)
  end

  def broadcast({tag, session} = event) when tag in [:session_started, :session_ended] do
    publish([sessions_topic() | thread_topics(session.thread_id)], event)
  end

  # A thread-scoped row may be unscoped (nil): then it belongs on no thread topic.
  defp thread_topics(nil), do: []
  defp thread_topics(thread_id), do: [thread_topic(thread_id)]

  defp publish(topics, event) do
    Enum.each(topics, &Phoenix.PubSub.broadcast(@pubsub, &1, event))
  end

  @doc """
  Announce a successful write: broadcast `{tag, row}` on an `{:ok, row}`, and pass
  the result straight through untouched otherwise. Lets a context end a write with
  `|> Bus.announce(:thread_opened)` — the row is durable before the nudge fires.
  """
  def announce({:ok, row} = result, tag) do
    broadcast({tag, row})
    result
  end

  def announce(result, _tag), do: result
end
