defmodule Funes.CheckTest do
  # Measured verification (roadmap #5): record_check lands a command's REAL exit code as
  # a check_passed/check_failed event, so "it works" is measured, never self-reported. The
  # kind is keyed on the number; the reads (CHECKS) surface the current verification state.
  use ExUnit.Case, async: false

  alias Funes.Channel
  alias Funes.Dossier

  setup do
    Funes.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "verify the drain"})
    %{thread: thread}
  end

  describe "record_check/1 — keyed on the real exit code" do
    test "exit 0 lands a check_passed event carrying the cmd + tail", %{thread: thread} do
      assert {:ok, event} =
               Dossier.record_check(%{
                 thread_id: thread.id,
                 cmd: "mise run check",
                 exit: 0,
                 tail: "135 tests, 0 failures"
               })

      assert event.kind == "check_passed"
      assert event.detail["cmd"] == "mise run check"
      assert event.detail["exit"] == 0
      assert event.detail["tail"] == "135 tests, 0 failures"
    end

    test "a non-zero exit lands a check_failed event", %{thread: thread} do
      assert {:ok, event} = Dossier.record_check(%{thread_id: thread.id, cmd: "mix test", exit: 1, tail: "1 failure"})
      assert event.kind == "check_failed"
      assert event.detail["exit"] == 1
    end
  end

  describe "recent_checks_for_thread/1 — CHECKS, newest first, capped + counted" do
    test "shows recent checks newest-first, cut at five with a count, thread-scoped", %{thread: thread} do
      {:ok, other} = Channel.open_thread(%{title: "other"})
      Dossier.record_check(%{thread_id: other.id, cmd: "elsewhere", exit: 0, tail: ""})

      for i <- 1..6, do: Dossier.record_check(%{thread_id: thread.id, cmd: "check #{i}", exit: rem(i, 2), tail: ""})

      %{shown: shown, more: more} = Dossier.recent_checks_for_thread(thread)
      assert length(shown) == 5
      assert more == 1
      # newest first: the last recorded (check 6, exit 0 → passed) heads the list
      assert hd(shown).detail["cmd"] == "check 6"
      assert Enum.all?(shown, &(&1.kind in ["check_passed", "check_failed"]))
      # the other thread's check is excluded
      refute Enum.any?(shown, &(&1.detail["cmd"] == "elsewhere"))
    end
  end
end
