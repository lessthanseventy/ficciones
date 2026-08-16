defmodule Funes.BoardTest do
  # The board's read models (aleph §4): the pure aggregates a TUI/LiveView renders.
  # IN FLIGHT is the roster (live sessions × warmth); IN SCOPE is one thread's brief
  # (NORTH STAR / SHIPPED / LEARNINGS / BLOCKERS / CHATTER) — the SAME one-call read
  # that briefs a re-entering session (§3b), so it is built once with two consumers.
  use ExUnit.Case, async: false
  alias Funes.{Board, Channel, Dossier, Repo, Staff}

  setup do
    Funes.TestDB.clean!()
    :ok
  end

  defp cold(session), do: set_active(session, 7200)

  defp set_active(session, seconds_ago) do
    at = DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)
    {:ok, s} = session |> Ecto.Changeset.change(last_active_at: at) |> Repo.update()
    s
  end

  describe "Staff.roster/0 — IN FLIGHT" do
    test "lists live sessions across threads with a warm/cold flag, omitting ended ones" do
      {:ok, thread} = Channel.open_thread(%{title: "one"})
      {:ok, sandra} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})

      {:ok, _warm} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, pane_ref: "wS"})

      {:ok, chilly} =
        Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, pane_ref: "wR"})

      {:ok, gone} =
        Staff.start_session(%{agent_id: sandra.id, thread_id: thread.id, pane_ref: "wG"})

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
    test "assembles NORTH STAR, lead, SHIPPED, LEARNINGS, BLOCKERS, CHATTER" do
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

      scope = Board.in_scope(thread)
      assert scope.north_star == "review PR 329"
      assert scope.lead == "Sandra"
      assert Enum.any?(scope.shipped, &(&1.kind == "work_landed"))
      assert Enum.any?(scope.learnings, &(&1.text == "a lesson"))
      assert Enum.any?(scope.blockers.shown, &(&1.summary == "a blocker"))
      assert Enum.any?(scope.chatter, &(&1.body == "starting"))
    end

    test "an unassigned thread has a nil lead" do
      {:ok, thread} = Channel.open_thread(%{title: "unstaffed"})
      assert Board.in_scope(thread).lead == nil
    end
  end
end
