defmodule Funes.Bus do
  @moduledoc """
  The reactive nudge over the durable bus (aleph §5). `Phoenix.PubSub` fans a posted
  message out to internal consumers — the switchboard today, the board later. This
  is *liveness only*: the message is already a durable row before it is broadcast,
  and a broadcast with no subscriber is a harmless no-op. Kill PubSub and nothing is
  lost; the switchboard's `drain/0` recovers from the DB.
  """
  @pubsub Funes.PubSub

  @doc "The topic every posted message is announced on."
  def topic, do: "funes:messages"

  @doc "Announce a posted message to internal consumers. Never the source of truth."
  def broadcast_message(%Funes.Message{} = message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(), {:message, message})
  end

  @doc "Subscribe the calling process to posted-message announcements."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, topic())
end
