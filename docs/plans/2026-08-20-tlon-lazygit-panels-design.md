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

- **Default focus = the terminal**; keys forward to tmux as today.
- The existing **`Ctrl+Space` leader** moves focus OUT of the terminal into nav mode:
  - `Ctrl+Space` then `1/2/3` → focus Commits / Memory / Leaves (or `Ctrl+Space Tab` cycles).
  - `Ctrl+Space 0` or `Esc` → return focus to the terminal (resume forwarding).
- A **focused side pane** owns `j/k` (move selection), `Enter` (open detail in MAIN), `Esc`
  (close detail → terminal), plus per-pane action keys.
- Detail views render in MAIN, temporarily replacing the terminal view; the tmux session keeps
  running underneath (it just stops receiving keys while a pane is focused).

This reuses the leader that already exists (`Aleph.Keymap`, `Ctrl+Space`), so it composes with the
tmux forwarding model instead of fighting it.

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

## Open decisions to confirm

1. Pane focus: `Ctrl+Space` + number vs. `Ctrl+Space Tab` cycle (or both).
2. Detail in MAIN (replaces terminal view) vs. a popup overlay over it.
3. Leaves `Enter`: switch to Sessions space, or show the brief in MAIN and stay in Tlön.
