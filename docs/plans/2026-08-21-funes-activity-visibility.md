# funes activity visibility — panel + footer pulse — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the opaque "funes · calling funes (2 tools)" with real visibility into the system: a live colored **Activity feed** panel in the Tlön space + an always-on **footer pulse** of the latest funes event, both fed by one global funes activity topic.

**Architecture:** `Funes.Bus` already broadcasts every durable write (`:fact_banked`, `:event_recorded` = checks+dones, `:message_posted`, `:issue_*`, `:question_*`, `:todo_*`) but only to per-thread topics — so a cross-agent feed can't see them. Add ONE global `activity` topic those events also publish to; the cockpit subscribes once, keeps a bounded buffer, and both surfaces render from it. All rendering is aleph's (the CC-hook route is a dead end — Claude Code won't paint a colored block from a hook).

**Tech Stack:** Elixir (funes `Phoenix.PubSub` bus; aleph raxol/termbox2 TUI, `Aleph.Panel` behaviour, `Aleph.Style` truecolor palette). Run mix via `mise exec -- mix`. aleph gate: `mise run aleph:check`.

**Discovery already done (exact entry points):**
- `modules/funes/lib/funes/bus.ex` — topic fns (`messages_topic`, `thread_topic`, `subscribe_*`) + `broadcast/1` clauses; the tagged events publish via `thread_topics(thread_id)`.
- `modules/aleph/lib/aleph/panel/chorus.ex` — the template feed panel (`@behaviour Aleph.Panel`, `topics/1`, `render/2` with `line/2` + `{text, style}` runs).
- `modules/aleph/lib/aleph/panel.ex` — `line/2`, `blank/0`, `clip/2`, the `style` type.
- `modules/aleph/lib/aleph/style.ex` — `@colors` map + `fg_bg/1`. Palette: green `#33FF00` body, amber `#FFB000` chrome, pink `#E0218A` accent, red `#FF5555` (`diff_del`), cyan `#33C7FF` (`diff_hunk`).
- `modules/aleph/lib/aleph/cockpit.ex` — `init` subscribes (`Bus.subscribe_messages/threads/sessions/habits`, ~L190); `handle_info({:message_posted, row}, state)` (~L387) is the repaint pattern.
- `modules/aleph/lib/aleph/panel/status_bar.ex` — the footer.
- `modules/aleph/lib/aleph/space.ex` — Tlön: `key: :tlon`, `left: [Stack, Memory]`, `right: [Health, Leaves]`.
- `modules/aleph/lib/aleph/view.ex` — `data_for/2` shapes sidebar-panel data (how Health/Leaves get theirs).

---

## Task 1: funes — a global `activity` topic on the bus

**Files:**
- Modify: `modules/funes/lib/funes/bus.ex`
- Test: `modules/funes/test/funes/bus_test.exs` (confirm path; else create)

**Step 1 (failing test):** assert that after `Bus.subscribe_activity()`, broadcasting a `:fact_banked` (and one `:event_recorded`, one `:message_posted`) delivers the event to the subscriber on the activity topic — independent of thread.

**Step 2:** run it, confirm FAIL (no `activity_topic`/`subscribe_activity`).

**Step 3 (implement):**
- Add `def activity_topic, do: "funes:activity"` and `def subscribe_activity, do: sub(activity_topic())`.
- In the `broadcast/1` clause for the tagged thread-scoped events (`:fact_banked`, `:event_recorded`, `:issue_raised`, `:issue_resolved`, `:todo_added`, `:todo_completed`, `:question_raised`, `:question_resolved`), append `activity_topic()` to the publish list. Do the same in the `:message_posted` clause.
- Keep per-thread topics intact (additive only).
- Document the topic in the moduledoc's topic list.

**Step 4:** run test → PASS. **Step 5:** full funes suite (`mise exec -- mix test`, no regressions). **Step 6:** commit `funes: global activity topic on the bus (cross-thread feed)`.

---

## Task 2: aleph — semantic event color styles

**Files:** Modify `modules/aleph/lib/aleph/style.ex`.

Add to `@colors` (reuse existing hues to stay on-palette), e.g.:
```elixir
    event_ok: {@green, @bg},          # fact banked, check passed
    event_bad: {0xFF5555, @bg},       # check failed (reuse diff_del red)
    event_msg: {0x33C7FF, @bg},       # message posted (reuse diff_hunk cyan)
    event_done: {@amber, @bg},        # work landed
    event_warn: {@amber, @bg},        # issue/question raised
```
No new test needed (pure data); `mise run aleph:check` covers compile. Commit with Task 3 or standalone: `aleph: semantic event styles for the activity feed`.

---

## Task 3: aleph — `Aleph.Panel.Activity` + cockpit buffer + Tlön mount

**Files:**
- Create: `modules/aleph/lib/aleph/panel/activity.ex`
- Modify: `modules/aleph/lib/aleph/cockpit.ex` (subscribe + buffer + handle_info), `modules/aleph/lib/aleph/view.ex` (`data_for/2` for the panel), `modules/aleph/lib/aleph/space.ex` (Tlön `right`)
- Test: `modules/aleph/test/aleph/panel/activity_test.exs`

**Step 1 (failing test):** `Aleph.Panel.Activity.render(%{events: [<sample fact_banked>, <sample check_failed>]}, rect)` returns rows containing the author + a summary, and the check-failed row uses the `:event_bad` style. Assert the empty-state row too.

**Step 2:** run, confirm FAIL (module missing).

**Step 3 (implement the panel):** mirror `chorus.ex`. `topics(_)` → `[]` (cockpit subscribes globally, like Chorus). `render(%{events: events}, rect)`: header `funes · activity`, then newest-first rows. Map each event to `{icon, style, text}`:
- `{:fact_banked, fact}` → `● ` `:event_ok`, `"fact ##{id} #{kind} — #{truncate(text)}"`, author from the fact's source session/agent if available.
- `{:event_recorded, ev}` → branch on `ev.kind`: `"check_passed"`→`✓ :event_ok`, `"check_failed"`→`✗ :event_bad`, `"work_landed"`→`⚑ :event_done`; summary from `ev.detail`.
- `{:message_posted, m}` → `▸ :event_msg`, `"#{m.author}: #{truncate(m.body)}"`.
- `{:issue_raised|:question_raised, row}` → `◆ :event_warn`.
- Truncate to the rect width; keep the newest N (buffer bound handled in the cockpit).

**Step 4 (cockpit wiring):**
- In `init`, add `Bus.subscribe_activity()`.
- Add `handle_info` clauses for the activity events (`{:fact_banked, _}`, `{:event_recorded, _}`, `{:message_posted, _}` [already handled — extend], `{:issue_raised, _}`, `{:question_raised, _}` …) that prepend `{tag, row}` to a bounded `state.activity` list (cap ~50) and repaint. NOTE: `:message_posted` already has a handler — fold the buffer append into it rather than duplicating.
- `Aleph.View.data_for/2`: return `%{events: state.activity}` for `Aleph.Panel.Activity` (mirror how Health/Leaves get their data).

**Step 5 (mount):** `space.ex` Tlön `right: [Health, Activity, Leaves]` (alias `Aleph.Panel.Activity`).

**Step 6:** `mise run aleph:check` green. **Step 7:** commit `aleph: funes activity feed panel in the Tlön space`.

---

## Task 4: aleph — footer pulse (latest event, always-on)

**Files:** Modify `modules/aleph/lib/aleph/panel/status_bar.ex` (+ `view.ex` if it needs the latest event in its data).

**Step 1 (failing test):** in the status_bar test (find/create), assert that given a latest activity event, the rendered footer contains a compact pulse segment (icon + author + short label), styled by the event's semantic style.

**Step 3 (implement):** add a right-aligned (or after the existing "no open blockers") segment showing `head(state.activity)` compactly: `funes ● fact #35 claude-machine`. Reuse the same event→{icon,style,text} mapping as the panel — extract that mapping into a shared helper (e.g. `Aleph.Panel.Activity.summarize/1`) so the panel and footer can't drift. Empty buffer → no pulse segment (don't crash).

**Step 4:** `mise run aleph:check` green. **Step 5:** commit `aleph: footer pulse — latest funes event always visible`.

---

## Definition of done

- `mise run aleph:check` green; funes `mix test` green.
- The Activity panel renders a colored, newest-first feed in Tlön's right column; the footer shows the latest event; both driven by real `Funes.Bus` traffic (verify live by banking a fact / posting a message and watching both update).
- Shared event→summary mapping (no panel/footer drift). Additive to the bus (per-thread topics unchanged).
