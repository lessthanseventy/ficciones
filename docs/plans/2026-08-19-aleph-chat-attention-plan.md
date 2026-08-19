# Aleph chat + attention layer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the aleph chat a real front door — a reply reliably wakes an agent, you choose who staffs a thread, a COWORKERS roster shows who's doing what and who's blocked on you, and you can jump to a live session.

**Architecture:** funes stays the source of truth (threads, staffing via `Staff.assign`, semantic signals). Aleph derives a per-coworker attention state by fusing funes signals with embedded-PTY motion, renders it in a left-rail roster, and routes operator replies to the staffed lead. Pure decision logic stays in testable modules (`Aleph.Mention`, `Aleph.Keymap`, a new `Aleph.Attention`); the `Aleph.Cockpit` GenServer stays a thin interpreter.

**Tech Stack:** Elixir/OTP, Ecto/SQLite (funes), raxol/termbox2 TUI, ghostty embedded terminals, tmux (Tlön coworker windows). Test runner: `mise run aleph:test` (pure seams) / `mise run aleph:check` (the gate: format + warnings-as-errors + headless suite).

**Design doc:** `docs/plans/2026-08-19-aleph-chat-attention-design.md`

**Scope of THIS plan:** Phase 1 (reply → wake the lead) is written in full, executable, TDD detail — it is the highest-value slice and fixes the origin "who am i talking to? → silence" bug. Phases 2–4 are scoped with exact files and approach but must each get their own detailed planning pass before execution (Phase 3's PTY-motion fusion in particular needs a spike). Ship Phase 1 first.

---

## Phase 1 — A bare reply wakes the thread's lead

**Problem it fixes:** today a posted message only wakes a coworker if it `@`-mentions one of the statically-named Tlön windows (`Aleph.Mention`). A plain operator reply to a thread wakes nobody — the silence Andrew hit. Fix: on a bare reply (no coworker `@`-mention), wake the thread's **lead** coworker (its funes `thread.agent_id`). `@`-mention still overrides and directs.

**Key facts from the codebase:**
- `Aleph.Mention.route/1` (`lib/aleph/mention.ex:72`) is pure, returns `[{window_name, text}]`, and already has the loop guard (never echo to the author's own window).
- The handle→window map is `@base_coworkers = %{"pi-machine" => "pi", "claude-machine" => "claude"}` (`mention.ex:23`).
- The cockpit edge `mention_notify/1` (`lib/aleph/cockpit.ex:424`) calls `Aleph.Mention.route(row)` then `tlon_window_index/1` + `inject_turn/2` (tmux send-keys). A window that isn't up is skipped.
- A thread has 0..1 staffed agent: `thread.agent_id`, set by `Funes.Staff.assign/2`. That agent IS the lead.
- `Funes.Channel` owns threads; `Funes.Staff.agent_by_name/1` and the `Thread` schema (`agent_id`) are the lookup surface.

### Task 1.1: `Aleph.Mention.route/2` accepts a lead and wakes it on a bare reply

**Files:**
- Modify: `lib/aleph/mention.ex` (add a 2-arity `route/2`; keep `route/1` delegating)
- Test: `test/aleph/mention_test.exs`

**Step 1 — Write the failing tests.** Append to `test/aleph/mention_test.exs`:

```elixir
describe "route/2 with a thread lead (bare-reply wake)" do
  test "a bare reply (no @-mention) wakes the thread's lead coworker" do
    assert Mention.route(
             %{author: "andrew", body: "who am i talking to?", thread_id: 9},
             lead: "claude-machine"
           ) == [{"claude", "[funes thread #9] andrew: who am i talking to?"}]
  end

  test "an explicit @-mention overrides the lead (directed, not the lead)" do
    assert Mention.route(
             %{author: "andrew", body: "@pi-machine you take this", thread_id: 9},
             lead: "claude-machine"
           ) == [{"pi", "[funes thread #9] andrew: @pi-machine you take this"}]
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
             [{"claude", "[funes thread #7] andrew: @claude-machine hi"}]
  end
end
```

**Step 2 — Run to verify it fails.**
Run: `cd /home/andrew/projects/ficciones/modules/aleph && mise run mix test test/aleph/mention_test.exs`
Expected: FAIL — `Mention.route/2 is undefined`.

**Step 3 — Implement `route/2`.** In `lib/aleph/mention.ex`, replace the `route/1` head + fallback (lines ~71–82) with:

```elixir
@doc """
The injection turns for a posted message. With an explicit coworker `@`-mention, wakes each
mentioned coworker (except the author's own window — the loop guard). With NO coworker mention,
falls back to `opts[:lead]` — the thread's staffed lead coworker — so a bare operator reply
still reaches someone. Each turn is `{window_name, one_line_text}`.
"""
@spec route(map(), keyword()) :: [{String.t(), String.t()}]
def route(row, opts \\ [])

def route(%{author: author, body: body, thread_id: tid}, opts) do
  author_window = coworkers()[author]
  targets = mention_targets(body, opts[:lead])

  for window <- targets, window != author_window do
    {window, "[funes thread #{tid_str(tid)}] #{display_author(author)}: #{one_line(body)}"}
  end
  |> Enum.uniq()
end

def route(_, _), do: []

# The windows to wake: the explicitly @-mentioned coworkers, or — when none are named — the
# thread's lead coworker's window (nil / unknown lead → []).
defp mention_targets(body, lead) do
  case mentions(body) do
    [] -> lead |> lead_window() |> List.wrap()
    ms -> Enum.map(ms, fn {_handle, window} -> window end)
  end
end

defp lead_window(nil), do: nil
defp lead_window(handle), do: coworkers()[handle]

defp one_line(body), do: String.replace(body || "", "\n", " ")
defp tid_str(nil), do: "?"
defp tid_str(tid), do: "##{tid}"
```

(Delete the now-inlined `tid_str`/`one_line` locals from the old `route/1` body.)

**Step 4 — Run to verify it passes.**
Run: `cd /home/andrew/projects/ficciones/modules/aleph && mise run mix test test/aleph/mention_test.exs`
Expected: PASS (all cases, old and new).

**Step 5 — Commit.**
```bash
cd /home/andrew/projects/ficciones
git add modules/aleph/lib/aleph/mention.ex modules/aleph/test/aleph/mention_test.exs
git commit -m "aleph: mention — route/2 wakes the thread lead on a bare reply"
```

### Task 1.2: `Aleph.Cockpit` resolves the thread's lead and passes it to `route`

**Files:**
- Modify: `lib/aleph/cockpit.ex` — `mention_notify/1` (line ~424)
- (No new unit test: `mention_notify` is a tmux-touching edge, not a pure seam — the pure logic is covered in 1.1. Verify live in Task 1.3.)

**Step 1 — Add a lead resolver + pass it in.** Change `mention_notify/1`:

```elixir
defp mention_notify(row) do
  lead = thread_lead(row)

  for {window, text} <- Aleph.Mention.route(row, lead: lead),
      index = tlon_window_index(window),
      not is_nil(index) do
    inject_turn(index, text)
  end

  :ok
end

# The funes handle of the coworker staffed on this message's thread (its lead), or nil.
# Read in-process (aleph boots funes); never crash the hub if the lookup fails.
defp thread_lead(%{thread_id: tid}) when not is_nil(tid) do
  Funes.thread_lead(tid)
rescue
  _ -> nil
catch
  :exit, _ -> nil
end

defp thread_lead(_), do: nil
```

**Step 2 — Add the `Funes.thread_lead/1` public surface.** Aleph may only call `Funes` exports (`:boundary` enforces it). In `modules/funes/lib/funes.ex`, add to the public API:

```elixir
@doc "The handle of the agent staffed on a thread (its lead), or nil."
defdelegate thread_lead(thread_id), to: Funes.Channel
```

And in `modules/funes/lib/funes/channel.ex`:

```elixir
@doc "The name of the agent staffed on `thread_id` (its lead), or nil if unassigned/absent."
def thread_lead(thread_id) do
  Repo.one(
    from t in Thread,
      join: a in Funes.Agent,
      on: a.id == t.agent_id,
      where: t.id == ^thread_id,
      select: a.name
  )
end
```

(Confirm `import Ecto.Query` and the `Thread`/`Repo` aliases are already present in `channel.ex` — add if missing.)

**Step 2b — Add a funes-side unit test** for `thread_lead/1` in `modules/funes/test/funes/channel_test.exs` (or the nearest existing channel test): assign an agent to a thread, assert `Channel.thread_lead(id)` returns its name; assert nil for an unassigned thread and for a missing id. Use the existing test's data-setup helpers.

**Step 3 — Run the funes + aleph suites.**
Run: `cd /home/andrew/projects/ficciones/modules/funes && mise run mix test test/funes/channel_test.exs`
Then: `cd /home/andrew/projects/ficciones/modules/aleph && mise run aleph:check`
Expected: PASS / green (format + warnings-as-errors + headless suite).

**Step 4 — Commit.**
```bash
cd /home/andrew/projects/ficciones
git add modules/funes/lib/funes.ex modules/funes/lib/funes/channel.ex \
        modules/funes/test/funes/channel_test.exs modules/aleph/lib/aleph/cockpit.ex
git commit -m "aleph+funes: wake a thread's lead coworker on a bare operator reply"
```

### Task 1.3: Live verification (Andrew, not automated)

The wake path touches tmux + a live coworker window, so it is out of the headless suite (per `aleph/AGENTS.md`). Verify by hand:

1. `mise run aleph:reset && uqbar` (fresh cockpit + wired tlon).
2. In Tlön, ensure a coworker (e.g. claude-machine) is the lead of a thread (staffed).
3. From the composer, post a bare reply (no `@`) to that thread.
4. Expect: the lead coworker's tmux window receives the turn and replies via `post_message`. No more silence.
5. Regression: an `@pi-machine` reply still wakes pi specifically; a coworker's own post never echoes to itself.

**Note the honest boundary:** Phase 1 wakes leads that are **tmux coworker windows** (Tlön). Waking a project-thread `Aleph.Terminal` session on a bare reply is the `Aleph.Arbiter` path and is folded into Phase 4's unified resolver. Phase 1 deliberately fixes the Tlön case first, where Andrew is actually working.

---

## Phase 2 — Pick who joins (staffing picker on thread-create)

> **Critical finding from Phase 1 live-verify (2026-08-19):** the Tlön **chat tab is a
> separate process** — `mix aleph.machine_chat` (`lib/aleph/machine_chat/loop.ex`), its own
> BEAM/tmux window — with its **own** wake path (`wake_mentions/3`, `loop.ex:216`) that calls
> `Aleph.Mention.route/1` (mentions only). Phase 1 patched `Aleph.Cockpit.mention_notify`, a
> DIFFERENT process the chat tab bypasses (comment at `loop.ex:214`: "our post is on our own
> bus, which the cockpit can't see"). So Phase 1's lead-fallback does NOT run for anything typed
> in the chat. Also `do_submit/2` (`loop.ex:199-211`) ALWAYS `Channel.open_thread(scope:
> "machine")` — a new, unstaffed thread per message — so there is no lead to wake regardless.
> **Two required Phase-2 tasks fall out of this:**
> 1. **Bridge the chat wake path:** in `machine_chat/loop.ex` `wake_mentions/3`, resolve the
>    thread's lead (`Funes.thread_lead/1`, added in Phase 1) and call `Aleph.Mention.route/2`
>    with `lead:` — mirroring the cockpit change, so a bare reply in the chat wakes the lead.
> 2. **Staff a lead on composer threads:** `do_submit/2` must assign the chosen coworker
>    (`Funes.Staff.assign/2`) as the new thread's lead — otherwise `route/2` still finds no lead.
>    This is the same "pick who joins" staffing below, applied to the machine-chat composer.
>
> Only once BOTH land does "type in the chat → someone answers" work end to end.
>
> **Note the Orbis↔Tlön wall is intentional** (Andrew, 2026-08-19): Orbis is project-scope,
> Tlön machine-scope, isolated by the scope `CHECK` (+ the cockpit's `.dev` db on :4041).
> Machine threads NEVER surface in Orbis — do not "fix" this; the reply/staffing work happens
> inside Tlön/machine-chat, not by crossing the wall.

**Needs its own detailed planning pass.** Scope:

- **`lib/aleph/keymap.ex`:** the `n` verb currently jumps straight to `%{kind: :new_thread}` → `{:create_thread, title}` (keymap.ex:78, 175). Add a second modal step `%{kind: :pick_agent, title, choices, index}` entered after the title submits, and a new effect `{:create_thread_staffed, title, agent}`. Keep the reducer pure; unit-test the new key transitions in `test/aleph/keymap_test.exs`.
- **`lib/aleph/cockpit.ex`:** `apply_effect({:create_thread, ...})` (cockpit.ex:580) hard-codes spawning `pi` via `spawn_onto/2` (cockpit.ex:635, `Application.get_env(:aleph, :spawn_agent, "pi")`). Add `apply_effect({:create_thread_staffed, title, agent})` that `Channel.open_thread` → `Staff.assign` the chosen agent as lead → `spawn_onto` with that agent. The agent choices come from `Aleph.Profiles` / the funes agent roster.
- **Decision:** for one chosen coworker, assign = lead. For multiple, lead = first chosen, the rest are additional sessions (funes allows many sessions per thread; `assign` sets the single `agent_id`). Confirm the multi-staff UX before building — MVP can be single-select.

---

## Phase 3 — COWORKERS roster panel + attention engine

**Needs its own detailed planning pass, AND a spike for PTY-motion.** Scope:

- **New pure module `lib/aleph/attention.ex`** (unit-tested like `mention.ex`): given funes reads (roster/warmth, open questions/blockers addressed to the operator, recent `record_done`) and a per-coworker motion flag, return each coworker's state ∈ `{:needs_you, :working, :done, :idle}` and a short "what it's doing" phrase. Do the **funes-signal half first** (deterministic, testable); the motion flag is a plain input it fuses.
- **New panel `lib/aleph/panel/coworkers.ex`** replacing the SETTINGS panel in the left rail (`lib/aleph/view.ex` / `lib/aleph/space.ex` wire the panels). Row = state dot + handle + phrase + thread tag. Data assembled in `Cockpit.render/1`'s stateful preamble, like the current `habits_read`/roster reads.
- **Spike (separate, before building the motion half):** how to observe embedded-PTY motion. Options to evaluate: sample `Aleph.Terminal`/ghostty output-byte counters between ticks; for tmux coworkers, `tmux` activity flags or `capture-pane` deltas. Decide the cheapest signal that says "produced output since last tick." Until the spike lands, the roster runs on funes signals alone (states collapse to needs-you / done / idle; no live "working").
- **funes reads used:** `Staff.roster`, `Presence.warm?`, and the dossier's open questions/blockers/`record_done` (via existing `Funes` exports; add exports if a needed read isn't surfaced — respect the `:boundary` rule).

---

## Phase 4 — Fusion, folded config, jump affordance, chat toggle

**Needs its own detailed planning pass.** Scope:

- **Motion fusion:** feed the Phase-3 spike's motion flag into `Aleph.Attention` so 🟡 working lights up live.
- **Folded per-coworker config:** expand a COWORKERS row to show/change its driver/model (the old SETTINGS `m`-verb function `{:cycle_coworker_model, profile}`, cockpit.ex:610, moves onto the selected coworker row) plus mandate/permissions read-out.
- **Unified reply→wake resolver:** generalize Phase 1 so a bare reply also wakes a project-thread `Aleph.Terminal` lead via `Aleph.Arbiter` (arbiter.ex), not just tmux windows — one resolver, two backends (tmux send-keys / `Arbiter.wake`), chosen by how the lead's session is embedded.
- **Jump-to-session affordance:** a key on a focused thread / selected roster row that switches to the Sessions space AND lands on that thread's terminal in one motion (today it's implicit via shared `focused_id`; make it explicit).
- **Chat attention-sort toggle:** a key to flip the chat/chorus between Slack-order (default) and attention-sorted; state lives in cockpit, applied in `panel/chorus.ex` / `panel/conversation.ex`.

---

## Sequencing & principles

1. **Ship Phase 1 first** — smallest diff, kills the silence bug, fully testable pure logic.
2. Re-plan each later phase with its own `writing-plans` pass; **do not** batch them.
3. DRY (one wake resolver, one attention module), YAGNI (single-select staffing MVP; funes-signal attention before motion), TDD (pure modules get failing-test-first), frequent commits (one per task).
4. Every aleph change is green under `mise run aleph:check` before commit; tmux/PTY-touching behavior is verified live by Andrew (it's out of the headless suite by design).
