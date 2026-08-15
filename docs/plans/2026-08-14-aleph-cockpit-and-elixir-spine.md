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

- an assigned **agent** — a named agent/role (see §3), optional
- an attached **live session** — a Herdr/tmux pane, stored as an **opaque reference** and asked for
  liveness *live* (§3 verbatim — never a cached copy of its properties), so you can **jump into** it
- its own accumulated **state**, and this is the point: **the `IN SCOPE` dossier *is* the thread.**
  `NORTH STAR`, `LEARNINGS`, `BLOCKERS`, `SHIPPED`, `CHATTER` are just `fact`, `issue`, `event`, and
  `message` rows scoped to that thread.

So `fact`/`event`/`issue`/`message` gain a `thread` reference. The thread is the spine everything hangs
from; the workspace hangs off the thread as a handle, not the other way around.

---

## 3 · Agents, sessions, and the five axes

**Agent vs session, settled.** A **agent** is the *durable* identity + profile — a row in the DB
(Sandra, Robert), outliving everything. A **session** ("the agent") is an *ephemeral* running instance of
an agent: in a pane, on an engine, working one thread — it compacts, forgets, and dies. That ephemeral
thing is §10's "session"; the agent is the employee, the session is the employee-at-their-desk-right-
now. Agent persists; sessions come and go.

An agent is a named identity **powered by an engine** and shaped by **five orthogonal axes.**

**The engine — what powers a session.** Harness (pi | claude-code | codex | aider) and model are coupled
in reality (some harnesses lock to a provider; each model has *strengths* — opus for the deep single
thing, codex for planning), so local config defines named **engines**: valid harness+model combos with
declared strengths. The design never names claude/codex/ollama — an agent states a **strength
requirement** ("planning", "deep reasoning", "cheap per turn", "long context", "not the weights under
review") and the local **engine registry** resolves it. On the home box that registry is roughly
`{ deep: claude-code+opus, planner: codex, cheap: ollama.com }`; on the work box, something else — all
config, none in the design (§8). A workflow may route *phases* to different strengths (plan on the
planner, execute on the deep engine) — the ex_cortex pipeline, a later extension, not day one.

**The five axes** — each grounded in something already in the spec:

| Axis | The question | = | Grounded in |
|---|---|---|---|
| **Context** | what it *knows* at spawn | mandate + its scoped facts + the always-loaded constraints | §4 loading |
| **Sight** | what it can *look at*, live | granted **read** sources — MCP, APM, repos, web | §8 grants (read) |
| **Hands** | what it can *do* | granted **write** / actions / tools | §8 grants (write) |
| **Trust** | what it does *without asking* | the trust line; above it, prompt | §8 proposal gate |
| **Sandbox** | *where* it runs | disposable sandbox vs local-with-grants | §4b disposable-exec |

Orthogonal on purpose, so the useful combinations are expressible: **wide Sight + no Hands** = a pure
reviewer (sees the whole system, touches nothing — §5b's fresh eyes); **long Trust + disposable Sandbox** =
trusted *and* blast-contained. Sandra: fat Context, wide Sight, real Hands, long Trust, open Sandbox.
Robert: thin everything, no Hands, short Trust, locked Sandbox.

"What needs prompting" and "what we trust it to do" are the *same line seen from both sides* — one axis
(Trust), not two.

**Not over-built:** the profile lives inline on the agent; no role/type hierarchy until enough
agents share a profile to justify one. Schema: `agent` = identity + mandate + engine-requirement +
the five axes; a `session` references an agent and a thread; a thread has `0..1` agent; an agent
maps to many threads. The board groups by agent or by thread — both queries, neither stored twice.

---

## 3b · The staff — presence, routing, and re-entry

Three pieces fall out of "Jimmy's on a 5-hour break."

**Presence.** A session's availability is *derived from its engine*: credits spent, rate-limit window
closed, host down = **clocked out**. The **roster** shows who's *on the clock*; you can't assign a thread
to an agent who's out.

**The warmth window — presence has a clock, and it is the prompt cache's (added 2026-08-15).** A coworker
who steps away stays cheap to resume only while their context is *warm*, and the vendor keeps a prompt
cache warm for **about an hour**. So an hour is the **away-budget**: within it a session is warm and
resuming is a poke; past it the cache is cold, the transcript costs a full window to re-ingest, and the
right move is not to resume the dead session but to **brief a fresh one from the dossier** (the re-entry
rule below). "Take notes before you go, and if you're gone over an hour, come back fresh." A cold, idle
session is therefore treated as **clocked out** even if its engine still has credit — staleness is a form
of absence.

**The wake must be presence-gated, or it burns the window.** This is the one operational hazard of "delivery
wakes the recipient" (§5b.2): a wake pokes a *real, paid* session, and the forums are full of "I resumed an
old thread and spent my whole five-hour allotment." Two guards, both settled while the switchboard was
built: **(1)** never poke a **clocked-out or cold** session — it would pay full re-ingestion for a nudge;
**(2)** a backlog is **coalesced** — a resumed thread with fifty unread is *one* "you have 50," never fifty
turns. Until presence exists to enforce (1), the terminal arbiter defaults to **inert** (pokes nothing), so
the mechanism is safe to run before its governor is built — but no auto-poking backend ships until the
gate does.

**Routing and cover.** Assignment is skill × availability × cost: the deep engine (opus) isn't spent on
filing; grunt drops to the intern (local, always-on); when a senior is out, a mid (ollama) covers. Pay
grade = engine cost.

**The night shift.** The intern — cheap, local, always-on — runs *preset checks on a loop* and
**escalates**: alert the STAKEHOLDER out-of-band (the phone, over Tailscale) or **ping a senior when
their window reopens.** "Ping Jimmy when he's back" is a scheduled job (Oban / OTP) keyed on presence:
defer the work, wake it when the engine returns. ex_cortex's `Sense`/background-jobs layer, named like a
person.

**Re-entry is a briefing, never a replay — the load-bearing one.** You cannot hand a returning (or fresh,
or cheap) session the thread's raw transcript: it blows the context window (RUNWAY) or *costs its entire
next window* to re-ingest. So a session is **briefed from the thread's dossier** — `NORTH STAR`,
`LEARNINGS`, `BLOCKERS`, `SHIPPED`, last `CHATTER` — never the transcript. This validates the design from
a second direction: the `IN SCOPE` dossier was built for the human's eyes but is *also* exactly what
catches a session up cheaply — one artifact, two consumers (§2). It is §4's discipline ("32 rows, not
277KB") made urgent, because re-ingestion now has a *price*. And it sharpens §6's "nothing lives only in
the prose" into something with teeth: **if a thread's state lives only in a transcript, no returning
session can catch up affordably** — the structured rows are the *resume-token*, not bookkeeping. So
**catch-up cost is a first-class budget**: the dossier is ranked and cut (§6) so briefing is cheap and
predictable, and "rejoin the running thread" is usually the wrong instinct — sessions die (§10), you
brief a new one.

## 4 · The board — panes and register

The surface labels are the corporate-deadpan register (DFW/Palahniuk, an HST sprinkle) — universally
legible because everyone's sat through that meeting, which is exactly why it survives §1 (poor eyesight,
forgets names) while still having a pulse. The theme lives in the **module** names (Borges); the daily
labels stay plain-corporate.

```
ACTION REQUIRED            IN FLIGHT
 threads needing you        agent · 9/11 · RUNWAY 67%

IN SCOPE  (the focused thread)
 NORTH STAR    ACTION ITEMS    SHIPPED
 LEARNINGS     BLOCKERS        CHATTER
```

| Label | Is | Table |
|---|---|---|
| ACTION REQUIRED | what needs the STAKEHOLDER now | blocked agents, approvals, PRs on my call, mentions |
| IN FLIGHT | live agents × threads; **RUNWAY** = ctx% (how much before compaction) | sessions + `event`; §8 pressure |
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

## 6b · The capability spine, and one register per layer

**§8 is the organizing principle, not a footnote about models.** The design names only two kinds of thing:
the **DB** (the one truth), and **capabilities** — each behind a thin adapter with a *local* backend:

- **terminal** (Herdr | tmux) · **harness/engine** (pi | claude-code | codex, resolved by strength) ·
  **model** (§8) · **credentials** (env | keychain | file | human) · **sources** (MCP | APM | repos)

Everything product-shaped is a swappable adapter; nothing in the design branches on which one. That is
*why* the second machine works (§8c): home box = claude-code + ollama.com + tmux; work box = pi +
frontier + Herdr — **same design, different config.** The harness was simply the adapter we hadn't named;
it provides three verbs — *spawn a session, read its transcript* (§4's turn-derivation), *and be woken.*

**One register per layer, so naming is four decisions and not a thousand (§1).** A name inherits its
layer's register; you never start from scratch:

| Layer | Read by / how often | Register | Examples |
|---|---|---|---|
| Module identities | learned once | Borges | `ficciones` `funes` `tlon` `aleph` |
| Daily surface labels | a thousand times | corporate-deadpan | `ACTION REQUIRED` `LEARNINGS` `RUNWAY` |
| Machine truth / data model | the machine + you at 2am | plain precise nouns | `thread` `agent` `session` `fact` `event` |
| Capability axes | you, configuring an agent | clear-with-teeth | `Context / Sight / Hands / Trust / Sandbox` |

`harness`, `arbiter`, `engine` are machine-truth → plain nouns, settled without debate.

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
  named agents.
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
3. **`agent`** — persistent named roles; assign to threads; jump-into-session.
4. **The dossier** — `fact`/`event`/`issue` scoped to threads → `LEARNINGS`/`SHIPPED`/`BLOCKERS`.
5. **aleph** — the Drafter board rendering all of the above, ranked and cut.
6. **Collectors** (`Sense`) — PR/calendar/etc., each honest about its `collection` row.

---

## 10 · Deferred, on purpose

- The web GUI (§7) — cheap later, unbuilt now.
- Consensus-voting clusters, self-improving/neuroplasticity (§8) — earned by evidence.
- The disposable-exec capability (prior doc §4b) — still designed, not built.
