# Tlön as lazygit — the panel rework

**Date:** 2026-08-20
**Status:** design + phased plan (Phase 0 building)
**Branch:** `funes-forgetting-engine` (rides after the forgetting-engine merge)

## The problem

Every panel that feels half-baked lives in ONE space — **Tlön**. Orbis (chorus+roster+dossier)
and Sessions (threadlist+terminal+dossier) are already tight. Tlön crams five mismatched panels
around the tertius terminal:

```
Tlön today:  left[ Stack, Settings ]  center( tertius terminal )  right[ Health, Orbis, Habits ]
```

`Stack` alone does three jobs (git changelog + tool versions + system state). The panels are a
grab-bag with N moods, no shared interaction model, and the terminal competes with 5 always-on
readouts.

## The vision: Tlön feels like lazygit

Not "N sidebars always on" but **a few focused, keyboard-navigable panes + a status bar**, where
the *active* pane is rich and the terminal is one pane among them.

```
Tlön reworked:
  ┌ Commits ────┐ ┌──────────────────────────────┐
  │ > a1b2  ... │ │  MAIN                          │
  │   c3d4  ... │ │  · tertius terminal (default)  │
  ├ Memory ─────┤ │  · OR the focused pane's       │
  │ floor 8 ... │ │    detail (a commit diff, a    │
  │ habit? ...  │ │    fact's strength, …)         │
  ├ Leaves ─────┤ │                                │
  │ t3 lead ... │ │                                │
  └─────────────┘ └──────────────────────────────┘
  funes↑ tlon↑ · nix#42 · disk 34% · mem 51% · branch · dirty         [status bar]
```

### Interaction model (the crux — Tlön's center is a live tmux client that eats keys)

CONFIRMED (Andrew, 2026-08-20): a **4-level spatial nav** — lazygit-ish with extras for the
three-column shape (left sidebar · center terminal/MAIN · right sidebar).

- **`Ctrl+Space`** — TOGGLE in/out of the center terminal. In-terminal → keys forward to tmux
  (today's behavior); out → nav mode, aleph owns keys. (Reuses the existing leader as a toggle.)
- **`j`/`k`** — move the selection cursor WITHIN the focused pane's list.
- **`Tab`** — cycle WITHIN a pane, across its sub-sections (e.g. Memory's coverage / floor /
  habits). A single-list pane has nothing to cycle.
- **`h`/`l`** — move to the prev/next pane UP/DOWN the current sidebar column.
- **`H`/`L`** — jump BETWEEN the left and right sidebar columns.
- **`Enter`** — open the selection's detail in MAIN (replaces the terminal view; tmux keeps
  running underneath). **`Esc`** — close detail / step back toward the terminal.
- Leaves **`Enter`** → switch to the Sessions space focused on that thread.

Layout stays three columns. This is a pure focus STATE MACHINE (which column, which pane in it,
which section, in-terminal?) — Phase 1 builds it as a tested reducer; render/tmux wiring hangs off
it.

Detail in MAIN (not a popup) and Leaves→Sessions are the confirmed answers to the open decisions.

## The panes

### Commits (was Stack, git-only)
- The commit log: `hash · relative · author · subject`, agent-authored styled by the co-author
  trailer (plumbing exists in `Aleph.Stack.commits/2`).
- `j/k` select, `Enter` → the commit's **diff** (files + hunks, scrollable) in MAIN.
- Tool-versions + system-state are REMOVED from here (they move to the status bar / Memory).
- Needs: `Aleph.Stack.show/1` (`git show <hash>` → diff text). Pure-ish, testable.

### Memory (unify coverage + floor + habits) — the novel pane
"What funes knows", closing the loop with the forgetting engine.
- **header**: coverage — `embedded 30/30 · floor 8 ~1.1k/4k tok · 7 forgotten`.
- **floor**: the always-loaded constraints (`Dossier.always_loaded_constraints/0`), pinned.
- **habits**: pending habits as **candidate constraints**; `a` approve → becomes a floor fact,
  `r` reject. Habits stop being a dangling mechanism and become the write-path into memory.
- `Enter` on a fact → its full text + strength/touches in MAIN.
- Needs funes: `Recall.coverage/0`, `Dossier.pending_habits/0`, `Dossier.approve_habit/1` +
  exports.

### Leaves (was Orbis panel, renamed)
- `Funes.Board.machine_overview/0` — each staffed thread: lead · next · blocker.
- `Enter` → jump to that thread (switch to Sessions focused there).
- Renamed so it stops colliding with the *Orbis space*.

### Health → status bar
- `funes↑ tlon↑ · nix#N · disk% · mem% · branch · dirty` — one line (`Aleph.Panel.StatusBar`
  exists). You glance at health; you don't study it. Frees a full slot.

### Settings → modal
- The coworker model-ring is a control you touch, not a readout you monitor. Key-invoked overlay
  (`Ctrl+Space ,`), dismissable. Frees a slot.

## Two principles underneath

1. **Monitor vs. act** — continuously-watched → pane; occasionally-done → modal/action.
2. **One visual language** — shared chrome (title + spacer + rows), glyphs, and color semantics
   (`accent`/`dim`/`separator`/`selected`) so the cockpit reads as one system.

## funes surface additions (Phase 0)

One-line diffs in `lib/funes.ex` (the reviewed surface), delegating to internal modules:

- `recall_coverage/0` → `%{facts, embedded, floor_count, floor_tokens, budget, model}`
- `floor/0` → `Dossier.always_loaded_constraints/0` (already exported via Dossier; alias for the pane)
- `pending_habits/0`, `approve_habit/1`, `reject_habit/1` → thin `Dossier`/`Habit` wrappers

All pure reads or single writes; unit-tested in funes (no TTY).

## Phasing (execute in reviewed batches)

- **Phase 0 — foundation (low-risk, tested):** funes reads/actions above + exports; `Aleph.Stack.show/1`.
- **Phase 1 — focus model (risky core):** pane-focus/nav infra + keymap (leader→pane, Tab cycle,
  Esc→terminal) + the Health status bar. The un-unit-tested render/keymap heart — drive it with
  the `verify` skill, not just tests.
- **Phase 2 — Commits pane:** log nav + diff detail in MAIN.
- **Phase 3 — Memory pane:** coverage + floor + habit approval.
- **Phase 4 — Leaves pane:** machine_overview + jump-to-thread.
- **Phase 5 — Settings modal.**
- **Phase 6 — visual-language cleanup pass.**

Phases 2–4 are independent once Phase 1 lands → parallelizable.

## Decisions (resolved 2026-08-20)

1. Pane focus: the 4-level `Ctrl+Space` toggle + `j/k` (item) · `Tab` (section) · `h/l` (pane in
   column) · `H/L` (column) scheme above.
2. Detail renders in MAIN, replacing the terminal view (Esc restores).
3. Leaves `Enter` → switch to the Sessions space on that thread.

## Layout: which pane goes where (proposed)

- LEFT column: **Commits**, **Memory** (the panes you study/act on)
- RIGHT column: **Leaves** (the overview/launcher)
- CENTER: terminal, or the focused pane's detail (MAIN)
- BOTTOM: status bar (Health)
- Settings: modal (`Ctrl+Space ,`)
