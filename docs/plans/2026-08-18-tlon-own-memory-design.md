# Tlön gets its own dossier/logbook — design

_2026-08-18. Status: built. Amends the 2026-08-17 per-space-profiles design, which made the `tlon`
profile `mcp: :none` (fully severed from funes)._

## Why

The Tlön coworker did work (a bugfix) and it left **no trace** — no logbook entry, no notes. Cause:
the `tlon` profile was `mcp: :none` **and** dropped the `/manos/pi/` funes adapter, so the coworker
had neither the tools to record nor the extension that auto-records. "Self-contained" had come to
mean *amnesiac*.

But self-contained is the right instinct — Tlön shouldn't mix into the shared/project channel. The
fix is not to reconnect it to the shared channel; it's to give it **its own** memory. And that
memory surface already exists: funes has a CHECK-guarded `scope` column (`"project"` vs `"machine"`,
`channel.ex` — "aleph Tlön isolation, 2026-08-16"), and the Tlön space's LOGBOOK + dossier panels
already read the **machine** thread (`cockpit.ex` `logbook_read/1`). So the machine thread *is*
Tlön's private dossier/logbook — the coworker just couldn't write to it.

The original `mcp:none` sever was itself a blunt fix for a routing bug the 2026-08-17 doc names:
the coworker "posts/banks into a thread the Tlön space doesn't even render." That thread was a
**project** thread. Bind the coworker to the **machine** thread instead and the same posting becomes
the feature we want.

## Decision: isolate by SCOPE, not a second DB

Considered a separate funes DB for Tlön (physical isolation). Rejected — YAGNI:

- funes is single-Repo; a second DB means a second Ecto Repo (touching every context) or a second
  funes process, plus a second migration path and panel routing. Real, permanent complexity.
- The `machine` scope already gives **logical** isolation enforced by a DB CHECK — Tlön data cannot
  appear in a project view. The physical-vs-logical delta doesn't cover a real risk here.
- Independent wipe (the one thing a separate DB buys) is a one-line scoped delete if ever needed.

## The change (two lines + a tool filter, in `Aleph.Profiles`)

The coworker is **already** spawned with a machine-thread identity: `machine_exports/1` mints it via
`Spawn.join(machine_thread, "pi-machine")` (or `Spawn.env(scope: "machine")` if none exists) and the
exports (`FUNES_MCP_URL`, `FUNES_THREAD`, `FUNES_AUTHOR`, token) are injected into the launch env.
The empty `mcp.json` was the only thing stopping it. So:

1. `mcp: :none` → `@tlon_funes_mcp` — a funes server entry (`url = ${FUNES_MCP_URL}`, auth via
   `funes-cli.sh bearer`, which mints from `FUNES_THREAD/AUTHOR` = the machine thread). Writes land
   on the machine scope; the DB CHECK keeps them off project threads.
2. `drop_extensions: ["/manos/pi/"]` → `[]` — the funes adapter returns, now pointed at the machine
   thread: its brief (resume with the machine dossier) and its every-8-turns auto-capture
   (facts/questions banked to the machine scope).

Tool filter — self-containment lives here:
- `excludeTools`: `register`, `consult_peer` (asks *other* local coworker agents), `open_thread`,
  `close_thread` (cross-thread). These would breach the boundary.
- `directTools`: `post_message, bank_fact, raise_issue, record_done, record_check, get_dossier,
  propose_habit` — the machine-work record/read loop.

Model-to-model consultation (`/consult`, `/fresh`, and the mid-turn consult tool) is **kept** — it's
a separate package (`manos/consult`) that spawns a no-funes delegate, so it never touched the funes
boundary. That's the "Sonnet asks Fable when stuck" path, and it stays.

## Not changed
- Read side: LOGBOOK/dossier panels already render the machine thread. No panel changes.
- `funes-recall.json` is read from a fixed `~/.pi/agent/` path (`manos/pi extension.ts:44`), so the
  profile needs no recall-config symlink.

## Verify
- `aleph:check` (241 tests) green; `profiles_test.exs` updated to assert the machine-scope wiring +
  the tool cuts.
- Live (operator): `aleph:run`, do a bit of work in Tlön, confirm a LOGBOOK entry appears and that
  `get_dossier` reflects it; confirm `consult_peer`/`open_thread` are absent from the tool list.
