# Tlön roadmap — the single "nothing dangles" tracker

**Date:** 2026-09-01
**Purpose:** Andrew asked to step back and make sure *everything* open gets done, nothing left
dangling — one doc encompassing all of it. This is that index. It inventories every open
thread with status + priority, and links out to the detailed design docs. Priority reflects
Andrew's framing: **he builds from the outside (via Claude Code) and the cockpit is mostly a
test window right now, so substance + not losing accumulated knowledge on a wipe lead. But
visuals and polish DO matter too — the cockpit visual tail is real work, just sequenced after
the substance, not dropped.**

Design docs this indexes:
- `2026-09-01-tlon-architecture-and-coworker-lifecycle-design.md` — WS2 + WS3 detail
- `2026-09-01-per-thread-reply-input-design.md` — shipped
- `2026-09-01-cockpit-homogenize-design.md` — WS4 (parked tail)

---

## Status (updated end-of-session 2026-09-01)

**WS1 (bootstrap knowledge) — essentially DONE. WS2 (coworker lifecycle) — DONE.** The remaining
gap to a live "post → coworker replies" is NOT server code — it's verifying the console actuation
path (`Console.Arbiter.spawn` → `Sessions.spawn_harness` boots a working agent) in the running
cockpit. Left: WS3 (one-brain refactor, big/later), WS4 (visual tail), WS5 (backlog).

## Shipped (this session, on `main`)

- Per-thread reply box (`54f1092`, `2db0f5b`) — live-verified.
- NOW activity backfill on restart (`7f197e8`).
- Test hygiene — hermetic `PI_CODING_AGENT_DIR` (`aa7530c`); console suite 874/0.
- **WS1.2** — folded the session's architecture decisions into the wipe-proof seed (`55446e8`).
- **WS2** — cold-lead ROTATION instead of stranding (`c1bdeb9`): the switchboard spawn-decision
  is warm-only, so a cold lead is rotated (fresh, brief-seeded) via the already-wired arbiter.
- **WS1.3** — fact-promotion (`24a6bf3`): `mix server.promote_fact` graduates a banked fact into
  `promoted_facts.exs`, merged by `Server.Seed` on every boot — learnings survive a wipe.
- Design docs (`f441c84`, `2fed2d4`, `4047e68`, and corrections `68c983c`).

## Already built, discovered while surveying (WS1.1 was a phantom)

- **Seed + boot wiring.** `Bootstrap.ensure` → `Seed.ensure_safe/0` applies `repo_knowledge.exs`
  idempotently on every boot. DONE.
- **Staffing is already wired + tested.** `Channel.open_thread` enforces a lead invariant —
  `designated_lead(workspace_id)` picks the roster's manager (first `builder` = `hronir`) and
  `ensure_lead_agent` register-or-gets `hronir-machine` (tested, `channel_test.exs:262`). So
  threads ARE born staffed and the lead agent IS registered — **WS1.1's premise was wrong** (it
  came from stale memory predating this work). The `0/6 live` is a runtime "no warm sessions"
  state, not a staffing gap.

---

## WS1 — Bootstrap knowledge (TOP PRIORITY: the wipe-proof brain)

The north star: **the seed is everything Tlön should know and be on a fresh boot** — so wiping
the DB never loses hard-won knowledge or leaves a dead, unstaffed world. The mechanism exists
(`priv/seed/repo_knowledge.exs`, applied idempotently); this workstream fills it out and keeps
it growing.

1. **Seed the roster + baseline staffing.** Add coworker agents (the roster) and a staffed
   default thread/lead to the seed so a fresh world is *functional*, not just knowledgeable —
   this is the direct fix for `0/6` / unstaffed threads (`maybe_spawn_absent` needs a lead). Fold
   the existing `do_seed_world` roster logic into `Server.Seed` (or call it from the same boot
   path) so there is ONE seed, not a separate manual step. Closes the "durable fix still TODO"
   from `funes-two-DB-roster-seam`.
2. **Grow the knowledge corpus.** Curate the genuinely useful things learned (this session and
   before) into `repo_knowledge.exs` as intent-keyed facts — the standing self-knowledge every
   wipe restores. Treat it like a version-controlled memory index.
3. **Fact-promotion path.** A way to take a valuable *session-banked* fact and promote it into
   the seed file so it survives the next wipe — e.g. `mix server.promote_fact <id>` (or a CLI/MCP
   verb) that appends the fact, keyed by its `intent`, into `repo_knowledge.exs`. Without this,
   learnings only reach the seed by hand and silently rot. This is the loop that makes the brain
   *accumulate* instead of resetting to a fixed baseline.
4. **(Stretch) Seed richness audit.** Decide what else belongs in the wipe-proof set: baseline
   worklines, standing tickets, the archetype/role catalog, key project dossiers.

Why first: it's the highest substance-per-effort, it's what Andrew explicitly asked for, the
infra already exists, and #1 unblocks WS2 (a staffed world is the precondition for a coworker to
spawn at all).

## WS2 — Coworker lifecycle (make it talk back)

Detail in the architecture/lifecycle design doc §5. Depends on WS1.1 (staffing).

1. **Cold dead-zone fix.** `Switchboard.has_live_session?/2` only checks `ended_at IS NULL`, so a
   *cold* session is neither woken (`recipients/1` excludes it) nor replaced (`maybe_spawn_absent`
   sees a session) → the message strands. Treat cold like absent.
2. **Fresh-seed-on-cold spawn.** A cold/offline lead gets a FRESH session seeded from
   `Board.brief(thread)` (dossier catch-up), never a `/resume` of a huge context — no burned
   5-hour window.
3. **End-to-end verify.** Post → `maybe_spawn_absent` → live coworker → reply, once staffed.

## WS3 — One-brain architecture (the big refactor, deliberate/later)

Detail in the architecture/lifecycle design doc §4. Andrew's stated future (web UI + Oban) makes
this the correct target; it is a real refactor, its own plan when the time comes.

1. **Cockpit as RPC client.** Stop embedding `:server`; the cockpit `:erpc`s into the always-up
   server node. Retire the embedded :4041/`.dev` second brain; one seeded real DB; `.dev` =
   test-only.
2. **Web UI** (Phoenix/LiveView) over the same always-up server.
3. **Oban** persistent/scheduled jobs (maintain sweeps, drain, warmth reaping, digests).
4. **SQLite → Postgres**, likely triggered by #2/#3. Build the client boundary first; migrate the
   store when Oban/web-UI land.

## WS4 — Cockpit visual tail (active, after the substance)

The reshape/homogenize plan (`2026-09-01-cockpit-homogenize-design.md`) is structurally done
(Slices A/B/C + D1/D2). Remaining **D3 Tickets kanban · D4 Notes cards + CREW colors · D5 config
menus** are visual polish — real work Andrew wants done, sequenced after WS1–WS2 substance, not
dropped. Pick these up alongside/after the lifecycle work; they don't block anything.

## WS5 — Misc dangling (backlog, not lost)

- **Notes-reimagined** — the AI-iteration box + obsidiantui-lite md store (its own brainstorm;
  bigger than the D4 card restyle).
- **lazygit → flake** — package the lazygit dependency into the nix flake.
- **console leaf/leader rename** — the deferred Slice-5 rename pass (hazards noted in
  `orchestrator-cockpit-plan`).

---

## Order of attack

1. **WS1.1** — seed the roster/staffing → world is functional, `0/6` fixed. *(smallest real unblock)*
2. **WS1.2 / WS1.3** — grow the corpus + the promotion path → the accumulating brain.
3. **WS2** — cold dead-zone + fresh-seed → it talks back.
4. **WS4** — the visual tail (D3–D5): real work, do alongside/after WS2; blocks nothing.
5. **WS3** — one-brain refactor, when web-UI/Oban actually start. Own plan.
6. **WS5** — named backlog, as desired.

Nothing above is lost: WS1–WS4 are all active work, WS5 is a named backlog.
