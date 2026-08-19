defmodule Aleph.MentionTest do
  @moduledoc """
  The @-mention router — who gets woken, and what they're shown. Pure: the cockpit edge does the
  tmux send-keys. The loop guard (never echo back to the sender) and the handle→window mapping are
  the two things that must not regress.
  """
  use ExUnit.Case, async: true

  alias Aleph.Mention

  test "an @-handle maps to its coworker window" do
    assert Mention.mentions("@claude-machine check MCP") == [{"claude-machine", "hronir"}]
    assert Mention.mentions("hey @tertius-machine") == [{"tertius-machine", "tertius"}]
  end

  test "a non-coworker @-handle is ignored (slack-style noise, not a route)" do
    assert Mention.mentions("@andrew nope") == []
    assert Mention.mentions("@pi-machine gone") == []
  end

  test "multiple mentions dedupe and keep first-seen order" do
    assert Mention.mentions("@claude-machine @tertius-machine @claude-machine") ==
             [{"claude-machine", "hronir"}, {"tertius-machine", "tertius"}]
  end

  test "route wakes every mentioned coworker EXCEPT the author's own window (loop guard)" do
    assert Mention.route(%{author: "tertius-machine", body: "@claude-machine check MCP", thread_id: 1}) ==
             [{"hronir", "[funes thread #1] tertius-machine: @claude-machine check MCP"}]

    assert Mention.route(%{author: "claude-machine", body: "@tertius-machine your turn", thread_id: 1}) ==
             [{"tertius", "[funes thread #1] claude-machine: @tertius-machine your turn"}]
  end

  test "the operator (not a coworker) mentioning the builder wakes it" do
    assert Mention.route(%{author: "andrew", body: "@claude-machine do the thing", thread_id: 7}) ==
             [{"hronir", "[funes thread #7] andrew: @claude-machine do the thing"}]
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
             [{"hronir", "[funes thread ?] andrew: @claude-machine hi"}]
  end

  describe "route/2 with a thread lead (bare-reply wake)" do
    test "a bare reply (no @-mention) wakes the thread's lead coworker" do
      assert Mention.route(
               %{author: "andrew", body: "who am i talking to?", thread_id: 9},
               lead: "claude-machine"
             ) == [{"hronir", "[funes thread #9] andrew: who am i talking to?"}]
    end

    test "an explicit @-mention overrides the lead (directed, not the lead)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius-machine you take this", thread_id: 9},
               lead: "claude-machine"
             ) == [{"tertius", "[funes thread #9] andrew: @tertius-machine you take this"}]
    end

    test "the lead is not woken by its own post (loop guard still holds)" do
      assert Mention.route(
               %{author: "claude-machine", body: "thinking out loud", thread_id: 9},
               lead: "claude-machine"
             ) == []
    end

    test "no lead and no mention wakes nobody (unchanged)" do
      assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 9}, lead: nil) == []
    end

    test "an unknown lead handle (not a coworker window) wakes nobody" do
      assert Mention.route(%{author: "andrew", body: "hi", thread_id: 9}, lead: "ghost") == []
    end

    test "route/1 is unchanged (no lead = old behaviour)" do
      assert Mention.route(%{author: "andrew", body: "just talking", thread_id: 1}) == []

      assert Mention.route(%{author: "andrew", body: "@claude-machine hi", thread_id: 7}) ==
               [{"hronir", "[funes thread #7] andrew: @claude-machine hi"}]
    end
  end

  describe "route/2 with a staffed per-thread window (B1.4)" do
    test "a bare reply on a staffed thread wakes ITS t<id> window, not the standing coworker" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 2},
               lead: "claude-machine",
               staffed_window: "t2"
             ) == [{"t2", "[funes thread #2] andrew: tell me a joke"}]
    end

    test "an explicit @-mention of the lead on a staffed thread also lands on t<id>" do
      assert Mention.route(
               %{author: "andrew", body: "@claude-machine ping", thread_id: 2},
               lead: "claude-machine",
               staffed_window: "t2"
             ) == [{"t2", "[funes thread #2] andrew: @claude-machine ping"}]
    end

    test "the staffed lead's own post wakes nobody (loop guard survives the redirect)" do
      assert Mention.route(
               %{author: "claude-machine", body: "thinking out loud", thread_id: 2},
               lead: "claude-machine",
               staffed_window: "t2"
             ) == []
    end

    test "a mention of a DIFFERENT coworker is not redirected (only the lead's window moves)" do
      assert Mention.route(
               %{author: "andrew", body: "@tertius-machine you take it", thread_id: 2},
               lead: "claude-machine",
               staffed_window: "t2"
             ) == [{"tertius", "[funes thread #2] andrew: @tertius-machine you take it"}]
    end

    test "nil staffed_window is the standing-thread path (no redirect)" do
      assert Mention.route(
               %{author: "andrew", body: "tell me a joke", thread_id: 1},
               lead: "claude-machine",
               staffed_window: nil
             ) == [{"hronir", "[funes thread #1] andrew: tell me a joke"}]
    end
  end
end
