# Coworker surfaces beyond Tlön — design

**Date:** 2026-08-17 · **Status:** proposed (settings slice built in the fable deep review;
the rest is backlog for the dogfood loop).

Tlön proved the shape: a space names a `coworker` profile (`Aleph.Space.coworker` →
`Aleph.Profiles`), the cockpit materialises it and spawns it into the center, and the profile
carries the four dimensions a coworker varies on (tools/MCP, model, persona, sandbox) — plus,
since the deep review, its own tmux server and a runtime model override (`Aleph.Config`). This
doc is how that machinery extends to the OTHER surfaces without inventing a second mechanism.

## 1 · What was built now (low-risk slice)

- **`Aleph.Config` + SETTINGS panel + `m` verb** — the coworker driver model is an operator knob
  persisted outside the code; `Profiles.fetch/1` is the one merge seam. Any future space with a
  `coworker` gets the panel's data for free (`settings_read` keys off `Space.coworker`, not
  `:tlon`).

## 2 · Proposed, in order of value

### a. Sessions coworkers go through profiles too (the unification)
Today `spawn_onto/2` launches the base `mise exec -- pi` with FUNES_* env — configured by
`:spawn_agent`/`:spawn_launcher` app env, not by a profile. Propose a `"project"` profile
(mcp `:base`, funes-brief kept, no sandbox — the current behaviour, reified) and
`Space :sessions, coworker: "project"`. Requires factoring `Cockpit.profile_launcher/1`:
the `env PI_CODING_AGENT_DIR=… pi …` core becomes `Profiles.command/1` (harness + flags),
and the tmux wrapper stays Tlön-only — Sessions PTYs stay bare pi. Payoff: the SETTINGS
panel then tunes the *project* coworkers' model per space, and profile knobs (persona,
sandbox) apply to project work, not just the machine thread.

### b. A `harness` dimension on Profile (claude-code coworkers)
`Profile` assumes pi. `modules/manos/claude-code/launch.sh` already launches Claude Code as a
funes citizen. Add `harness: :pi | :claude` (default `:pi`) whose `command/1` resolves to the
right launcher; the Tlön tab strip already renders any window the operator opens by hand, so the
first use is cheap: a "Support Desk" window/profile that is Claude-driven while pi stays the
machine grunt. This is also where the Claude-billing decision gets a clean lever: the harness is
a profile field, not plumbing.

### c. Support Desk space (the escalation surface)
A space with `coworker: "desk"` (harness claude or pi-on-claude, persona "you are the
escalation desk; the operator brings you the problems the machine coworker couldn't close"),
centered on its own `scope: "machine"`-style thread (needs a third scope value or reuse of
machine scope with a distinct mandate — spec amendment territory, so: migration + spec edit in
the same commit, per the house rule). Left sidebar: Triage (already cross-thread); right:
Dossier. The point: today escalation means leaving the cockpit for a terminal; this makes it a
Tab press.

### d. Chat-first surfaces (Comms wake affordance)
`c` posts as the operator and the switchboard wakes the assigned agent — but the cockpit shows
no trace of the wake. Small slice: after a post, flash the wake decision ("woke Sandra" / "no
live session — Enter to spawn"), read from the switchboard's existing decision path. No new
mechanism, just surfacing one that exists.

## 3 · Settings surface growth (as knobs earn a UI)

The SETTINGS panel is deliberately a list of knob rows; next candidates, each one small PR:
thinking level (same ring pattern), per-space coworker profile picker (once ≥2 profiles exist),
`spawn_agent`, notification toggles (once herdr/OSC-777 notify lands). The rule: a knob enters
the panel when the operator actually changed it twice by editing files — the same "earned
generality" bar funes uses.
