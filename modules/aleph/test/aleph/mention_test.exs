defmodule Aleph.MentionTest do
  @moduledoc """
  The @-mention router — who gets woken, and what they're shown. Pure: the cockpit edge does the
  tmux send-keys, this just decides. The loop guard (never echo back to the sender) and the
  handle→window mapping are the two things that must not regress.
  """
  use ExUnit.Case, async: true

  alias Aleph.Mention

  test "an @-handle maps to its coworker window" do
    assert Mention.mentions("@claude-machine check MCP") == [{"claude-machine", "claude"}]
    assert Mention.mentions("hey @pi-machine") == [{"pi-machine", "pi"}]
  end

  test "a non-coworker @-handle is ignored (slack-style noise, not a route)" do
    assert Mention.mentions("@andrew nope") == []
  end

  test "multiple mentions dedupe and keep first-seen order" do
    assert Mention.mentions("@claude-machine @pi-machine @claude-machine") ==
             [{"claude-machine", "claude"}, {"pi-machine", "pi"}]
  end

  test "route wakes every mentioned coworker EXCEPT the author's own window (loop guard)" do
    # pi mentioning claude → claude is woken, pi (the sender) is not.
    assert Mention.route(%{author: "pi-machine", body: "@claude-machine check MCP", thread_id: 1}) ==
             [{"claude", "[funes thread #1] pi-machine: @claude-machine check MCP"}]

    # claude mentioning pi → pi is woken, claude is not.
    assert Mention.route(%{author: "claude-machine", body: "@pi-machine your turn", thread_id: 1}) ==
             [{"pi", "[funes thread #1] claude-machine: @pi-machine your turn"}]
  end

  test "the operator (not a coworker) mentioning claude wakes claude" do
    assert Mention.route(%{author: "andrew", body: "@claude-machine do the thing", thread_id: 7}) ==
             [{"claude", "[funes thread #7] andrew: @claude-machine do the thing"}]
  end

  test "a multiline body is flattened to one line (tmux send-keys is line-based)" do
    routed = Mention.route(%{author: "andrew", body: "@claude-machine line one\nline two", thread_id: 1})
    assert [{_window, text}] = routed
    assert text == "[funes thread #1] andrew: @claude-machine line one line two"
  end

  test "a message with no mention routes nowhere" do
    assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 1}) == []
  end

  test "a message missing thread_id still routes (with '?' for the id)" do
    assert Mention.route(%{author: "andrew", body: "@claude-machine hi", thread_id: nil}) ==
             [{"claude", "[funes thread ?] andrew: @claude-machine hi"}]
  end
end
