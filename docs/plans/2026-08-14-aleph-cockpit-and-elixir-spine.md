# aleph — the cockpit, thread-as-atom, and the Elixir spine

Written 2026-08-14, the turn the whole thing coalesced. `funes` was never going to be a pile of CLIs; it
is a **TUI Slack for agents** that is the owner's primary workspace. This document captures that shape
so it stops living in a transcript — which is, pointedly, the exact failure §4 exists to prevent.

Supersedes the runtime decision in `2026-08-14-machine-v2-and-funes-design.md` §2 (Node/TS): the
persistent, reactive, coordination-centric system described here is an Elixir one. The reasoning is in §5.

---

## 1 · aleph — what it is

**aleph** is the cockpit: a terminal UI (later possibly a GUI too) that is a Slack-style board for the
owner and his agents. Borges' Aleph is the point from which every place is seen at once; the cockpit is
that point for one person's machine and its work. It lives in a privileged Hyprland workspace as the
place he dwells, with a companion **SUGGESTION BOX** (the F12 drop-down quake terminal) always one
keystroke away for capture.

`funes` remembers, `tlon` is the desktop world, **`aleph` is where you see it all** — the third Borges
module, and the first-class one.

---

## 2 · The atom is the thread

Everything reduces to one object. **You open a thread on the board; the thread is the unit of work.** A
thread is a subject (§5b's "a thread per subject", and the spec's `subject` tag) promoted to a
first-class row. It carries:

- an assigned **coworker** — a named agent/role (see §3), optional
- an attached **live session** — a Herdr/tmux pane, stored as an **opaque reference** and asked for
  liveness *live* (§3 verbatim — never a cached copy of its properties), so you can **jump into** it
- its own accumulated **state**, and this is the point: **the `IN SCOPE` dossier *is* the thread.**
  `NORTH STAR`, `LEARNINGS`, `BLOCKERS`, `SHIPPED`, `CHATTER` are just `fact`, `issue`, `event`, and
  `message` rows scoped to that thread.

So `fact`/`event`/`issue`/`message` gain a `thread` reference. The thread is the spine everything hangs
from; the workspace hangs off the thread as a handle, not the other way around.

---

## 3 · Coworkers — persistent named identities with capability profiles

A coworker is **persistent** (handles many threads over time, not spun per-thread — this was the open
question) and it is a **named identity bound to a capability profile.** "Sandra, our Support agent, wired
to the APM and the MCPs and trusted with more power" versus "Robert, who is dumb and sandboxed hard" is
not flavour — it is a different profile. Five parts:

1. **Identity + mandate** — a name, so `Sandra reviewed it` outlives the workspace (§5b), plus a one-line
   mandate.
2. **Capability requirement, not a product (§8)** — the model tier it *needs*, as a requirement: "cheap
   per turn", "long context", "not the weights under review". The mapping to an actual endpoint is local
   config; the design never names a model.
3. **Grants** — opaque references to what it may reach: MCP servers, data sources (an APM, a tracker),
   repos, tools — each read-only or read/write. The design holds the *reference and the read/write bit*;
   local config resolves "the support MCP" or "the APM" to a real endpoint and secret. Robert's grants
   are empty; Sandra's are broad.
4. **Autonomy** — how much it may do without a proposal gate (§8, "the human presses Enter"). Robert:
   everything gated. Sandra: acts within her grants, escalates writes.
5. **Execution posture** — where its commands run: hard sandbox / disposable-exec (prior doc §4b) for
   Robert; local-with-grants for Sandra.

This is just §8 applied to a coworker — capability requirements plus local grants, no product in the
design — and it composes cleanly with the proposal gate (autonomy), disposable-exec (posture), and the
channel (a coworker posts to threads *as* its identity). The v1 "Dashboard", "Reviews", and "Support
Desk" sessions were each an early, profile-less version of this.

**Not over-built:** the profile lives inline on the coworker. No separate role/type hierarchy until there
are enough coworkers sharing a profile to justify factoring one out — the spec's own "don't build it
before the evidence." Schema: `coworker` = identity + mandate + capability requirement + grants +
autonomy + posture; a thread has `0..1` assigned coworker; a coworker maps to many threads. The board
groups by coworker or by thread — both queries, neither stored twice.

---

## 4 · The board — panes and register

The surface labels are the corporate-deadpan register (DFW/Palahniuk, an HST sprinkle) — universally
legible because everyone's sat through that meeting, which is exactly why it survives §1 (poor eyesight,
forgets names) while still having a pulse. The theme lives in the **module** names (Borges); the daily
labels stay plain-corporate.

```
ACTION REQUIRED            IN FLIGHT
 threads needing you        coworker · 9/11 · RUNWAY 67%

IN SCOPE  (the focused thread)
 NORTH STAR    ACTION ITEMS    SHIPPED
 LEARNINGS     BLOCKERS        CHATTER
```

| Label | Is | Table |
|---|---|---|
| ACTION REQUIRED | what needs the STAKEHOLDER now | blocked agents, approvals, PRs on my call, mentions |
| IN FLIGHT | live coworkers × threads; **RUNWAY** = ctx% (how much before compaction) | sessions + `event`; §8 pressure |
| NORTH STAR | the thread's goal/heading | `orient` |
| ACTION ITEMS | what's next | queue |
| SHIPPED | what landed | `event` |
| LEARNINGS | what we found | `fact` |
| BLOCKERS | what's open | `issue` |
| CHATTER | what's being said | `message` (channel) |

The register **generates**: `STANDUP` (the board), `KICKOFF` (session start / orient), `EOD` (daily
note), `THE RETRO` (week view), `PARKING LOT` (deferred issues), `STAKEHOLDER` (the sole human). These
were not on any list an hour ago; the metaphor coughed them up.

Rules unchanged: rank and cut, cap and count (§6); render from disk instantly, refresh behind the human;
an empty collector says so (`collection`, §4); Herdr/tmux vocabulary, no invented nouns (§3).

---

## 5 · Runtime — the Elixir spine, the SQLite ledger

The Node/TS decision was correct for "a pile of short-lived CLIs" — BEAM's per-invocation boot tax killed
Elixir there. That premise is gone. A **persistent, reactive, coordination-centric** system is where OTP
dominates and the boot tax vanishes: "invocations" become messages to an already-running node.

- **OTP supervision tree** owns the long-lived parts: collectors (`Sense`-style GenServers), reactivity,
  the aleph cockpit.
- **`Phoenix.PubSub`** does double duty: reactive fan-out to the board *and* §5b's "delivery wakes the
  recipient."
- **SQLite stays the truth** — Ecto over `ecto_sqlite3`, the *same single file* already schema'd, still
  `sqlite3`-inspectable and JSONL-exportable, still 2am-repairable. **Not Postgres** — the single-file,
  measured, repairable choice is load-bearing (§4). This is the one place ficciones diverges hardest from
  `ex_cortex` (see §8).
- **Drafter** (Elixir, LiveView-shaped TUI) renders aleph, in-stack.
- **Ports / escape hatches** for exactly two things: the terminal **arbiter** (Herdr/tmux shell) and the
  **external agent sessions**, which are not Elixir processes by design (§10) and speak only through the DB.

Re-verify the §4 write contract on `exqlite` (busy_timeout, retry-once, WAL) before trusting it — the
spec's numbers were `node:sqlite`; prove it, don't assume.

**The Node day-one-step-1 (db, migrate, doctor) is superseded in plan.** What carries over is
language-neutral and already correct: the schema (`001-core.sql`, `collection`), the write contract, and
doctor's responsibilities. The port to Ecto migrations + a `mix` doctor task is the first build step of
the new plan; the Node code is reference until then, not load-bearing.

---

## 6 · The one line we do not cross (§10)

"Move Herdr's inter-agent comms into the Elixir stack" is the right instinct and the exact place §10
lives. The legal form:

- **The DB (SQLite) is the durable bus.** Every message, thread, and state change is a row. *This is
  truth.*
- **Elixir is the switchboard** — routing, presence, the reactive board, delivery via PubSub. *This is
  liveness.*
- **Invariant:** kill the entire BEAM node and **no message is lost, and every agent can still read and
  write the DB directly.** The switchboard makes it *live*; it must never be what makes it *exist*. The
  moment an agent can only communicate *through* Elixir, the meta-orchestrator §10 forbids is back.

The honest twist: a *supervised, DB-backed* switchboard **fulfils §10's intent better than v1 did.** §10
bans an *unreliable, ephemeral session* from the delivery path — they compact and die. OTP + SQLite-as-
truth is the opposite of ephemeral, and v1's herdr-mailbox dropped messages and woke no one. This fixes
that — *provided the ledger stays authoritative.*

**Division of labour: Elixir orchestrates, the arbiter actuates.** PubSub wakes *internal* consumers (the
board). Waking an *external* agent session — a real pi/Claude terminal — still needs the arbiter to poke
the pane (`herdr agent prompt` / tmux `send-keys`). Elixir decides *who* to wake; Herdr/tmux does the
poking. And the arbiter itself is a **capability, not a product** (Herdr | tmux), local config picks the
backend — the same §8 rule the spec applied to models and credentials, now applied to the one place the
spec violated it by naming Herdr throughout.

---

## 7 · UI-agnostic domain — TUI now, GUI later for free

Keep the domain pure: Ecto contexts over SQLite hold all coordination logic; a front-end is only a view.
**Drafter TUI now**; a Phoenix LiveView web GUI is possible *later* over the *same* contexts — which is
precisely what `ex_cortex` already proves works. Build the second view when there's a reason; the
data-structure discipline that makes it cheap is the point of doing it now.

---

## 8 · ex_cortex — take the patterns, leave the weight

The owner's prior attempt (`lessthanseventy/ex_cortex`) is the maximal version of this instinct:
Elixir/Phoenix/LiveView, multi-agent clusters, `Sense` collectors, `Proposal` approval gates, tiered
memory, a self-rewriting loop.

- **Its patterns are confirmed and reused.** `Sense` = signal collectors (§9.3). `Proposal`
  (read-executes, write-requires-approval) = §8's "the human presses Enter" — and it appears in **all
  three** systems (ex_cortex, v1, the spec), so it is an invariant, not a preference. Named neurons =
  named coworkers.
- **Its substrate is what the spec spent itself avoiding.** Postgres + Oban + OpenTelemetry + Grafana +
  neuroplasticity is a data-center. ficciones is the disciplined cut: SQLite, TUI-first, rank-and-cut,
  build-it-only-for-the-channel. Consensus-voting clusters and self-rewriting code are *earned by
  evidence, later* — not day one.

---

## 9 · Build order, re-laid

db + doctor still ships first — repairable-at-2am is non-negotiable (§9.1). But the **channel/thread is
now the spine**, so it moves up:

1. **DB + doctor**, on the Elixir spine (Ecto migrations, `mix` doctor). Schema carries over from the
   Node work; re-verify the write contract on `exqlite`.
2. **`thread` + `message` + delivery/wake** — the board's spine and §4's capture path (the SUGGESTION
   BOX writes here). `delivered` ≠ `read`. PubSub fan-out; arbiter wake.
3. **`coworker`** — persistent named roles; assign to threads; jump-into-session.
4. **The dossier** — `fact`/`event`/`issue` scoped to threads → `LEARNINGS`/`SHIPPED`/`BLOCKERS`.
5. **aleph** — the Drafter board rendering all of the above, ranked and cut.
6. **Collectors** (`Sense`) — PR/calendar/etc., each honest about its `collection` row.

---

## 10 · Deferred, on purpose

- The web GUI (§7) — cheap later, unbuilt now.
- Consensus-voting clusters, self-improving/neuroplasticity (§8) — earned by evidence.
- The disposable-exec capability (prior doc §4b) — still designed, not built.
