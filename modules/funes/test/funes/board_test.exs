defmodule Funes.BoardTest do
  # The board's read models (aleph §4): the pure aggregates a TUI/LiveView renders.
  # IN FLIGHT is the roster (live sessions × warmth); IN SCOPE is one thread's brief
  # (NORTH STAR / TODOS / NEXT / DONE / LEARNINGS / BLOCKERS / CHATTER) — the SAME
  # one-call read that briefs a re-entering session (§3b), one read, two consumers.
  # DONE is a MERGED view: completed todos by their `done_at` + `work_landed` events.
  use ExUnit.Case, async: false

  alias Funes.Board
  alias Funes.Channel
  alias Funes.Dossier
  alias Funes.Repo
  alias Funes.Staff

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  defp cold(session), do: set_active(session, 7200)

  defp set_active(session, seconds_ago) do
    at = DateTime.utc_now() |> DateTime.shift(second: -seconds_ago) |> DateTime.truncate(:second)
    {:ok, s} = session |> Ecto.Changeset.change(last_active_at: at) |> Repo.update()
    s
  end

  describe "Staff.roster/0 — IN FLIGHT" do
    test "lists live sessions across threads with a warm/cold flag, omitting ended ones" do
      {:ok, thread} = Channel.open_thread(%{title: "one"})
      {:ok, other} = Channel.open_thread(%{title: "two"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})

      {:ok, _warm} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, pane_ref: "wS"})

      {:ok, chilly} =
        Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, pane_ref: "wR"})

      # Sandra's ended session lives on a SECOND thread — a second live session on
      # the same (thread, agent) would be superseded, not coexist (the zombie guard).
      {:ok, gone} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: other.id, pane_ref: "wG"})

      cold(chilly)
      {:ok, _} = Staff.end_session(gone)

      roster = Staff.roster()
      refs = Enum.map(roster, & &1.pane_ref)
      assert "wS" in refs
      assert "wR" in refs
      refute "wG" in refs

      assert Enum.find(roster, &(&1.pane_ref == "wS")).warm? == true
      assert Enum.find(roster, &(&1.pane_ref == "wR")).warm? == false
      assert Enum.find(roster, &(&1.pane_ref == "wS")).agent == "Sandra"
    end
  end

  describe "Board.in_scope/1 — IN SCOPE" do
    test "assembles NORTH STAR, lead, TODOS/NEXT/DONE, LEARNINGS, BLOCKERS, CHATTER" do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, sandra)

      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "Sandra", body: "starting"})

      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "a lesson",
          provenance: "derived"
        })

      {:ok, _} =
        Dossier.record_event(%{
          thread_id: thread.id,
          kind: "work_landed",
          detail: %{"summary" => "merged"}
        })

      {:ok, _} = Dossier.raise_issue(%{thread_id: thread.id, summary: "a blocker"})
      {:ok, _} = Dossier.raise_question(%{thread_id: thread.id, text: "does raxol embed?"})
      {:ok, _} = Dossier.record_check(%{thread_id: thread.id, cmd: "mise run check", exit: 0, tail: "ok"})

      {:ok, planned} = Dossier.add_todo(%{thread_id: thread.id, text: "planned step"})
      {:ok, _done} = Dossier.complete_todo(planned)
      {:ok, _} = Dossier.add_todo(%{thread_id: thread.id, text: "open step"})

      scope = Board.in_scope(thread)
      assert scope.north_star == "review PR 329"
      assert scope.lead == "Sandra"
      # DONE is a MERGED view: the completed todo AND the work_landed event, tagged by source
      assert Enum.any?(scope.done.shown, &(&1.source == :event and &1.row.kind == "work_landed"))
      assert Enum.any?(scope.done.shown, &(&1.source == :todo and &1.row.text == "planned step"))
      # the open steps, and NEXT — the first open todo, derived
      assert Enum.any?(scope.todos.shown, &(&1.text == "open step"))
      assert scope.next.text == "open step"
      assert Enum.any?(scope.learnings.shown, &(&1.text == "a lesson"))
      assert Enum.any?(scope.unknowns.shown, &(&1.text == "does raxol embed?"))
      assert Enum.any?(scope.checks.shown, &(&1.kind == "check_passed"))
      assert Enum.any?(scope.blockers.shown, &(&1.summary == "a blocker"))
      assert Enum.any?(scope.chatter, &(&1.body == "starting"))
    end

    test "LEARNINGS and DONE are capped WITH a count — a cut without a count lies" do
      # The silent-cap failure (pi doc §2b): for an agent whose only window into
      # its memory is this brief, "5 shown" with no number for the rest reads as
      # "5 exist" — the empty-world lie in miniature. Same shape as blockers.
      {:ok, thread} = Channel.open_thread(%{title: "t"})

      for n <- 1..7 do
        {:ok, _} =
          Dossier.bank_fact(%{
            thread_id: thread.id,
            kind: "learned",
            text: "fact #{n}",
            provenance: "derived"
          })
      end

      for n <- 1..6 do
        {:ok, _} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "work_landed",
            detail: %{"summary" => "landed #{n}"}
          })
      end

      scope = Board.in_scope(thread)
      assert length(scope.learnings.shown) == 5
      assert scope.learnings.more == 2
      # DONE here is 6 work_landed events (no todos) — capped at five with the count.
      assert length(scope.done.shown) == 5
      assert scope.done.more == 1
    end

    test "an unassigned thread has a nil lead, and empty sections count zero" do
      {:ok, thread} = Channel.open_thread(%{title: "unstaffed"})
      scope = Board.in_scope(thread)
      assert scope.lead == nil
      assert scope.learnings == %{shown: [], more: 0}
      assert scope.unknowns == %{shown: [], more: 0}
      assert scope.checks == %{shown: [], more: 0}
      assert scope.done == %{shown: [], more: 0}
      assert scope.todos == %{shown: [], more: 0}
      assert scope.next == nil
    end
  end
end
