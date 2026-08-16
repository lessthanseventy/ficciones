# Tlön — the machine coworker (design + session handoff)

**Date:** 2026-08-16 · **Status:** v1 shipped; v1.1 (pi citizen) in progress
**Why this doc exists:** the human's Claude 5‑hour window was near full — this is the
resumption point so an interruption loses nothing. Pick up at **v1.1 scope** below.

## Where things stand

- **Tlön v1 is shipped** (`9ed33f4`): the "Issues" space became **Tlön**, the META space for
  working ON the machine/stack as a whole (not a project). Shape: **STACK** (left — recent
  `ficciones` commits, `Aleph.Stack.commits/2`) · **center** · **TOOLS** (right — pi/claude/nix/
  mise/tmux versions, `Aleph.Stack.tools/0`, cached). Confirmed rendering live.
- The center is currently a **bare `$SHELL`** (`machine_terminal/0` in `cockpit.ex`). That is the
  thing v1.1 replaces.

## The decision (this session)

Tlön's center should be an **agent working on the box with you**, not an empty prompt.

**Default harness = pi**, and it's not close — for the reason `AGENTS.md` already encodes: *push
work down to the cheapest bucket that can still do it well.* claude is the scarce bucket (5‑hr /
weekly caps); pi rides the flat $20 all‑nighter. Tlön work is **meta** — triage, changelogs,
nix/mise poking, "what should I work on," filing issues — orchestration, not code‑implementation.
Auto‑spawning pi is ~free; auto‑spawning claude would drain the scarce bucket. **claude stays the
deliberate escalation** for implement‑with‑auto‑mode. (Human confirmed this lean.)

## The vision (evolving — the human's framing)

Tlön's agent is a **dedicated, standing coworker** — a machine/env specialist. *"Every company
has tech support and HR."* Not a per‑task temp; a persistent employee:

- **Its own config** — custom pi (and claude) configs tuned for machine work: specific **MCPs**,
  curated **knowledge/skills**, a **persona/mandate**. (This is what the background extension
  survey feeds — see below.)
- **Persistent** — a standing agent on a persistent machine thread, warm across the day.
- **Maybe both pi AND claude available** — the human said "tmux tabs." Architecturally, aleph no
  longer uses tmux for sessions (it embeds real ghostty terminals), so this becomes: **multiple
  center sessions / a harness switch** in the Tlön center (pi tab + claude tab).
- **Eventually several standing coworkers by mandate** — "tech support" (machine/infra specialist)
  first; "HR" (agent/thread coordination, onboarding, who‑works‑on‑what) later.

## v1.1 scope — SHIP NOW (the foundation)

Replace the bare shell with **pi as a funes citizen**:

- `machine_terminal/0`: fast path is `Sessions.terminal(:machine)` (a bare lookup every render).
  Slow path (first Tlön entry only): `Funes.MCP.Spawn.env("Tlön", "pi-machine", mandate:
  "machine")` → open a persistent machine thread + mint identity + build the `FUNES_*` exports →
  `Sessions.spawn_harness(:machine, exports)` (default launcher `mise exec -- pi`). Keyed
  `:machine` in the registry (decoupled from the real funes thread id in the exports), so it's
  spawned once and reused.
- Effect: switch to Tlön → a briefed pi coworker comes up, registered in `funes:roster`, its work
  (issues it files, checks it runs) remembered and triageable.

**Known v1.1 limitation:** opens a *new* "Tlön" thread per aleph boot (no find‑or‑create by
title). Acceptable for now; refinement is find‑or‑create the latest open machine thread.

## Next iterations (captured, NOT built — anti‑scatter)

1. **The coworker CONFIG bundle** — a dedicated manos config for the machine coworker: its MCPs,
   skills, knowledge, persona. Fed by the extension survey (below).
2. **Harness switch in the Tlön center** — pi ↔ claude (claude for implement‑with‑auto‑mode);
   possibly both loaded as separate center sessions ("tabs").
3. **Multiple standing coworkers by mandate** — tech‑support (now), HR/coordination (later).

   **Agent‑about‑agent feedback (the "HR" idea, de‑metaphored).** Every funes object today is about
   *work or the machine* (facts/todos/questions/issues/checks) — none has a **coworker** as its
   subject. So an agent can say "the code is broken" but not "Bob is the problem." That's a real gap
   in a multi‑agent system. Keep it honest by demanding **actionable state** from each thing the
   metaphor suggests: "Bob keeps hitting the sandbox" (→ fix his allowlist) and "Bob is
   thrashing / burning the Claude bucket" (→ reassign, downgrade, clock out) are real; "Bob should be
   funnier" is the metaphor overreaching — not a primitive. **Minimal shape: don't invent a new
   object or a department — give `issue` an optional agent subject (`about_agent`) and let triage
   (Uqbar) show "issues about coworkers" as their own lane.** "Who do they tell?" = the human's
   triage inbox now; the **supervisor / "HR" standing coworker** later — a *consumer* of that signal
   (watches roster warmth, thrash, bucket burn, repeated peer‑issues and acts), i.e. the literal‑HR
   reading done right, one of the coworkers‑by‑mandate. NOT built; captured so the metaphor doesn't
   generate grievance theater.
4. **`Panel.Uqbar`** — the triage inbox (the status bar already stubs "triage inbox"): `issue`
   rows filed from other sessions + a keybind + input modal (reuse the `n` new‑thread pattern).
   funes' `issue` table + `raise_issue` MCP already exist. Name approved: **Uqbar** ("deviating
   from the path"); funes keeps `:issue` as the vocabulary.

## Also in flight this session

- **`watch:stop` mise task** — a safe manual stop for stray watchers, using the `[w]atchexec`
  bracket idiom (see the pkill footgun below).
- **Extension survey** — a background agent is surveying the pi extension ecosystem
  (`pi.dev/packages`) for prior art to crib into the coworker's config/extension, writing
  **`docs/research/2026-08-16-pi-extension-prior-art.md`**. Commit that file when it lands.

## The pkill footgun (so it is never rediagnosed as "flaky tests")

`pkill -f <pattern>` / `pgrep -f <pattern>` match each process's **entire command line** — and the
shell running the command has the pattern string in its **own argv**, so it signals **itself** →
exit 143/144. Worse, `pkill -f "beam.*aleph"` matched the **test BEAM** that `mise run aleph:check`
had just spawned and killed it mid‑suite → the "sh exited with non‑zero status / no exit status"
noise. **The suite was green every clean run — there was never a flake.** Fixes: never `pkill` for
cleanup; use the `[w]atchexec` bracket idiom (a regex that does not appear literally in its own
argv), or the harness's own background‑task controls.
