defmodule Aleph.MentionEnvTest do
  @moduledoc """
  The experiment knobs on the @-mention router — the third voice ($TLON_THIRD_AGENT) and the
  anonymised sender label ($TLON_MENTION_LABEL). async: false: these mutate process-global env, so
  they must not run concurrently with the pure MentionTest route cases (which assert real labels).
  """
  use ExUnit.Case, async: false

  alias Aleph.Mention

  setup do
    on_exit(fn ->
      System.delete_env("TLON_THIRD_AGENT")
      System.delete_env("TLON_MENTION_LABEL")
    end)

    :ok
  end

  describe "TLON_THIRD_AGENT — an optional third coworker" do
    test "is nil when unset, and parses handle:window when set" do
      System.delete_env("TLON_THIRD_AGENT")
      assert Mention.third_agent() == nil

      System.put_env("TLON_THIRD_AGENT", "skeptic-machine:skeptic")
      assert Mention.third_agent() == %{author: "skeptic-machine", window: "skeptic"}
    end

    test "malformed values degrade to no third agent, never a crash" do
      System.put_env("TLON_THIRD_AGENT", "nowindow")
      assert Mention.third_agent() == nil
      System.put_env("TLON_THIRD_AGENT", ":")
      assert Mention.third_agent() == nil
    end

    test "the third agent joins the wake-loop — @-mention wakes its window" do
      System.put_env("TLON_THIRD_AGENT", "skeptic-machine:skeptic")

      assert Mention.coworkers()["skeptic-machine"] == "skeptic"

      assert Mention.route(%{author: "pi-machine", body: "@skeptic-machine weigh in", thread_id: 1}) ==
               [{"skeptic", "[funes thread #1] pi-machine: @skeptic-machine weigh in"}]

      # And the base pair still works alongside it.
      assert Mention.route(%{author: "skeptic-machine", body: "@claude-machine you're stalling", thread_id: 1}) ==
               [{"claude", "[funes thread #1] skeptic-machine: @claude-machine you're stalling"}]
    end
  end

  describe "TLON_MENTION_LABEL=anon — strip the sender persona" do
    test "labels the injected turn 'someone' instead of the real handle" do
      System.put_env("TLON_MENTION_LABEL", "anon")

      assert Mention.route(%{author: "pi-machine", body: "@claude-machine who are you", thread_id: 1}) ==
               [{"claude", "[funes thread #1] someone: @claude-machine who are you"}]
    end

    test "any other value keeps the real label" do
      System.put_env("TLON_MENTION_LABEL", "real")

      assert Mention.route(%{author: "pi-machine", body: "@claude-machine hi", thread_id: 1}) ==
               [{"claude", "[funes thread #1] pi-machine: @claude-machine hi"}]
    end
  end
end
