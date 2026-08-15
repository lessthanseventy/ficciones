defmodule Funes.DossierTest do
  # Step 4: the dossier (aleph §9.4, spec §4/§5). `fact`, `event`, and `issue`
  # scoped to a thread are the thread's accumulated state — LEARNINGS, SHIPPED,
  # BLOCKERS. The DB is the bus (§10): every assertion reads back through SQLite.
  use ExUnit.Case, async: false
  alias Funes.{Channel, Dossier, Event, Fact, Issue, Repo}

  # Shared DB, no sandbox (like steps 2–3). Clear domain rows first, children
  # before parents, so no FK dangles. fact/event reference thread + session; both
  # go after them.
  setup do
    Repo.delete_all(Fact)
    Repo.delete_all(Event)
    Repo.delete_all(Issue)
    Repo.delete_all(Funes.Session)
    Repo.delete_all(Funes.Message)
    Repo.delete_all(Funes.Thread)
    Repo.delete_all(Funes.Agent)
    :ok
  end

  describe "bank_fact/1 — the ledger's successor (§4)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      %{thread: thread}
    end

    test "banks a durable fact that reads back through SQLite", %{thread: thread} do
      {:ok, fact} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "exqlite sets busy_timeout via a NIF, not PRAGMA",
          provenance: "derived",
          check_cmd: "mix test test/funes/write_contract_test.exs"
        })

      reloaded = Repo.get!(Fact, fact.id)
      assert reloaded.thread_id == thread.id
      assert reloaded.kind == "learned"
      assert reloaded.text == "exqlite sets busy_timeout via a NIF, not PRAGMA"
      assert reloaded.provenance == "derived"
      assert reloaded.check_cmd == "mix test test/funes/write_contract_test.exs"
      assert %DateTime{} = reloaded.created_at
    end

    test "a fact can be global — the always-loaded constraints are not thread-scoped (§4)" do
      # provenance='stated' AND kind='constraint' is loaded every session, machine-
      # wide, so thread_id must be nullable.
      {:ok, fact} =
        Dossier.bank_fact(%{
          kind: "constraint",
          text: "In production, Andrew presses Enter.",
          provenance: "stated"
        })

      assert Repo.get!(Fact, fact.id).thread_id == nil
    end

    test "kind, text, and provenance are required", %{thread: thread} do
      assert {:error, cs} =
               Dossier.bank_fact(%{thread_id: thread.id, text: "t", provenance: "stated"})

      assert %{kind: _} = errors_on(cs)

      assert {:error, cs} =
               Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", provenance: "stated"})

      assert %{text: _} = errors_on(cs)

      assert {:error, cs} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "t"})
      assert %{provenance: _} = errors_on(cs)
    end

    test "kind is a closed set — SQLite's CHECK refuses anything else (§4)", %{thread: thread} do
      # No app-side validate_inclusion mirrors the CHECK (§2, single source of
      # truth): a bad kind is refused by the DB and raises, exactly like a bad
      # thread state in step 2.
      assert_raise Ecto.ConstraintError, fn ->
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "opinion",
          text: "t",
          provenance: "derived"
        })
      end
    end

    test "provenance is a closed set — only stated | derived, the DB refuses the rest", %{
      thread: thread
    } do
      # 'measured' was proposed and rejected (§4): it never carried the property
      # anyone wanted, and reproducibility lives in check_cmd instead.
      assert_raise Ecto.ConstraintError, fn ->
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "t",
          provenance: "measured"
        })
      end
    end

    test "supersedes must point at a real fact — the FK is the DB's guard", %{thread: thread} do
      assert_raise Ecto.ConstraintError, fn ->
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "constraint",
          text: "t",
          provenance: "stated",
          supersedes: 999_999
        })
      end
    end

    test "source_session_id must point at a real session — the FK is the DB's guard", %{
      thread: thread
    } do
      assert_raise Ecto.ConstraintError, fn ->
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "t",
          provenance: "derived",
          source_session_id: 999_999
        })
      end
    end
  end

  describe "the reproducibility axis (§4)" do
    test "check_cmd is optional — a derived fact without one is our lowest-ranked opinion" do
      {:ok, fact} = Dossier.bank_fact(%{kind: "learned", text: "a hunch", provenance: "derived"})
      assert Repo.get!(Fact, fact.id).check_cmd == nil
    end
  end

  describe "event.detail — a JSON column (Funes.JSONColumn)" do
    test "an absent detail round-trips as nil, not an empty map" do
      {:ok, event} = Dossier.record_event(%{kind: "handoff_opened"})
      assert Repo.get!(Event, event.id).detail == nil
    end

    test "detail rejects a non-map value — it is JSON for a human, not a free string" do
      assert {:error, cs} = Dossier.record_event(%{kind: "work_landed", detail: "not a map"})
      assert %{detail: _} = errors_on(cs)
    end
  end

  describe "always_loaded_constraints/0 — the 32 rows every session reads (§4)" do
    test "returns only stated constraints, not derived facts, decisions, or learnings" do
      {:ok, _keep} =
        Dossier.bank_fact(%{kind: "constraint", text: "presses Enter", provenance: "stated"})

      {:ok, _derived_constraint} =
        Dossier.bank_fact(%{kind: "constraint", text: "derived rule", provenance: "derived"})

      {:ok, _stated_decision} =
        Dossier.bank_fact(%{kind: "decision", text: "chose Elixir", provenance: "stated"})

      {:ok, _stated_learned} =
        Dossier.bank_fact(%{kind: "learned", text: "a lesson", provenance: "stated"})

      texts = Dossier.always_loaded_constraints() |> Enum.map(& &1.text)
      assert texts == ["presses Enter"]
    end

    test "a superseded constraint drops out — superseding is explicit, never by recency (§4)" do
      {:ok, old} =
        Dossier.bank_fact(%{
          kind: "constraint",
          text: "notes stay authored by him",
          provenance: "stated"
        })

      {:ok, _new} =
        Dossier.bank_fact(%{
          kind: "constraint",
          text: "the machine may own the daily note",
          provenance: "stated",
          supersedes: old.id
        })

      # Both are stated constraints and they conflict; the one something supersedes
      # is retired, so only the superseding one is loaded.
      texts = Dossier.always_loaded_constraints() |> Enum.map(& &1.text)
      assert texts == ["the machine may own the daily note"]
    end

    test "a derived fact cannot retire a stated constraint — stated outranks derived (§4)" do
      # His constraints outrank our conclusions by construction (§4). Only a peer —
      # another stated constraint — may retire one; a derived fact pointing at it
      # must NOT launder a paraphrase into his instruction.
      {:ok, stated} =
        Dossier.bank_fact(%{kind: "constraint", text: "his rule", provenance: "stated"})

      {:ok, _derived} =
        Dossier.bank_fact(%{
          kind: "learned",
          text: "we think otherwise",
          provenance: "derived",
          supersedes: stated.id
        })

      texts = Dossier.always_loaded_constraints() |> Enum.map(& &1.text)
      assert texts == ["his rule"]
    end
  end

  describe "facts_for_thread/1" do
    test "returns a thread's facts, scoped to it, newest first" do
      {:ok, t1} = Channel.open_thread(%{title: "one"})
      {:ok, t2} = Channel.open_thread(%{title: "two"})

      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: t1.id,
          kind: "learned",
          text: "first",
          provenance: "derived"
        })

      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: t1.id,
          kind: "learned",
          text: "second",
          provenance: "derived"
        })

      {:ok, _} =
        Dossier.bank_fact(%{
          thread_id: t2.id,
          kind: "learned",
          text: "theirs",
          provenance: "derived"
        })

      texts = Dossier.facts_for_thread(t1) |> Enum.map(& &1.text)
      assert texts == ["second", "first"]
    end
  end

  describe "record_event/1 — append-only, what happened (§4)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      %{thread: thread}
    end

    test "records a durable event that reads back through SQLite", %{thread: thread} do
      {:ok, event} =
        Dossier.record_event(%{
          thread_id: thread.id,
          kind: "work_landed",
          correlation: "pr-329",
          detail: %{"summary" => "merged the context gate fix"}
        })

      reloaded = Repo.get!(Event, event.id)
      assert reloaded.thread_id == thread.id
      assert reloaded.kind == "work_landed"
      assert reloaded.correlation == "pr-329"
      # detail is JSON for a human to read, never queried (§4) — it round-trips.
      assert reloaded.detail == %{"summary" => "merged the context gate fix"}
      assert %DateTime{} = reloaded.created_at
    end

    test "kind is required", %{thread: thread} do
      assert {:error, cs} = Dossier.record_event(%{thread_id: thread.id})
      assert %{kind: _} = errors_on(cs)
    end

    test "kind is a CLOSED set — a database CHECK refuses anything else (§4)", %{thread: thread} do
      # An open string is the wide-discriminator failure §4 rejects; adding a kind
      # is a migration, which is the point. The DB is the guard (§10) — not mirrored.
      assert_raise Ecto.ConstraintError, fn ->
        Dossier.record_event(%{thread_id: thread.id, kind: "vibed"})
      end
    end

    test "an event may be global — a lifecycle event need not be thread-scoped" do
      {:ok, event} = Dossier.record_event(%{kind: "handoff_opened"})
      assert Repo.get!(Event, event.id).thread_id == nil
    end

    test "correlation groups a multi-row lifecycle — never inferred from text (§4)", %{
      thread: thread
    } do
      {:ok, _} =
        Dossier.record_event(%{thread_id: thread.id, kind: "handoff_opened", correlation: "h-1"})

      {:ok, _} =
        Dossier.record_event(%{thread_id: thread.id, kind: "work_landed", correlation: "h-1"})

      grouped = Dossier.events_for_thread(thread) |> Enum.filter(&(&1.correlation == "h-1"))
      assert length(grouped) == 2
    end
  end

  describe "shipped_for_thread/1 — the 'work landed' outcome (§9.4)" do
    test "returns only work_landed events, not the mechanism kinds around them" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "handoff_opened"})
      {:ok, _} = Dossier.record_event(%{thread_id: thread.id, kind: "check_passed"})

      {:ok, _} =
        Dossier.record_event(%{thread_id: thread.id, kind: "work_landed", correlation: "a"})

      {:ok, _} =
        Dossier.record_event(%{thread_id: thread.id, kind: "work_landed", correlation: "b"})

      kinds = Dossier.shipped_for_thread(thread) |> Enum.map(& &1.kind) |> Enum.uniq()
      assert kinds == ["work_landed"]
      assert length(Dossier.shipped_for_thread(thread)) == 2
    end
  end

  describe "raise_issue/1 — a finding that outlives its session (§5)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      %{thread: thread}
    end

    test "raises a durable issue that reads back through SQLite", %{thread: thread} do
      {:ok, issue} =
        Dossier.raise_issue(%{
          thread_id: thread.id,
          summary: "the reusable workflow sets up neither Elixir nor Playwright",
          evidence: "docs/ci-run-4821.log",
          resolution: "add the setup steps to the shared workflow",
          found_by: "Robert"
        })

      reloaded = Repo.get!(Issue, issue.id)
      assert reloaded.thread_id == thread.id
      assert reloaded.summary == "the reusable workflow sets up neither Elixir nor Playwright"
      assert reloaded.evidence == "docs/ci-run-4821.log"
      assert reloaded.resolution == "add the setup steps to the shared workflow"
      assert reloaded.found_by == "Robert"
      assert reloaded.state == "open"
      assert %DateTime{} = reloaded.created_at
    end

    test "a summary is the one required field — the rest of the ticket is optional (§5)", %{
      thread: thread
    } do
      assert {:error, cs} = Dossier.raise_issue(%{thread_id: thread.id})
      assert %{summary: _} = errors_on(cs)
    end

    test "state is a closed set — SQLite's CHECK refuses anything else", %{thread: thread} do
      {:ok, issue} = Dossier.raise_issue(%{thread_id: thread.id, summary: "x"})

      assert_raise Ecto.ConstraintError, fn ->
        issue |> Ecto.Changeset.change(state: "wontfix") |> Repo.update()
      end
    end

    test "an issue can be unscoped — an unowned finding lives in the coordination surface (§5)" do
      {:ok, issue} = Dossier.raise_issue(%{summary: "something is broken somewhere"})
      assert Repo.get!(Issue, issue.id).thread_id == nil
    end
  end

  describe "resolve_issue/1" do
    test "closes an issue — read back through SQLite" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      {:ok, issue} = Dossier.raise_issue(%{thread_id: thread.id, summary: "x"})

      {:ok, resolved} = Dossier.resolve_issue(issue)
      assert resolved.state == "closed"
      assert Repo.get!(Issue, issue.id).state == "closed"
    end
  end

  describe "open_issues_for_thread/1 — the orient/BLOCKERS read (§5 acceptance)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      %{thread: thread}
    end

    test "returns a thread's open issues, scoped to it, and omits closed ones", %{thread: thread} do
      {:ok, other_thread} = Channel.open_thread(%{title: "elsewhere"})
      {:ok, _open} = Dossier.raise_issue(%{thread_id: thread.id, summary: "still open"})
      {:ok, done} = Dossier.raise_issue(%{thread_id: thread.id, summary: "already fixed"})
      {:ok, _} = Dossier.resolve_issue(done)
      {:ok, _theirs} = Dossier.raise_issue(%{thread_id: other_thread.id, summary: "not mine"})

      %{shown: shown, more: more} = Dossier.open_issues_for_thread(thread)
      assert Enum.map(shown, & &1.summary) == ["still open"]
      assert more == 0
    end

    test "caps at five lines and counts the rest — rank and cut (§5)", %{thread: thread} do
      # Seven open issues on one thread: show five, the rest is a number, never a
      # complete-and-useless list (§1).
      for n <- 1..7 do
        {:ok, _} = Dossier.raise_issue(%{thread_id: thread.id, summary: "finding #{n}"})
      end

      %{shown: shown, more: more} = Dossier.open_issues_for_thread(thread)
      assert length(shown) == 5
      assert more == 2
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
