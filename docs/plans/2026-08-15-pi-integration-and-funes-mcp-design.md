# pi integration — the funes MCP channel, a pi extension, skills, and bootstrap

Written 2026-08-15, opening the **agent-side** of the stack. **Revised the same day**, after a
fresh-context adversarial design review and an owner clarification about `issue`. The prior docs built
the **memory** (`modules/funes/`) and the **face** (`modules/aleph/`); this one is about the **hands** —
how **pi** (the agent, `github.com/earendil-works/pi`) plugs into the harness so the dossier's facts /
opinions / unknowns / todos / done becomes *real writes from a working agent*, not an empty cache. A
dossier with no agent feeding it is the "cache that reports an empty world is a lie" failure at the top
of the stack.

The revision changed four things, each named here rather than silently (the spec's own amendment
discipline):

1. **The certainty axis is a QUERY, not a type.** The first draft gave `fact` a
   `kind: :fact | :opinion` and a stored `confidence`. The review caught that funes already encodes
   uncertainty — spec §4's total order over `provenance` × `check_cmd`, whose own text names
   `derived AND check IS NULL` as "our unverifiable opinions." A second encoding beside the first is
   the two-sources failure, opinion-in-`kind` is the second-dimension-in-a-discriminator failure the
   spec already rejected once (attribution), and a stored numeric confidence is an invented number
   nothing ever updates. See §4a.
2. **`issue` is the stack's tracker; `question` is the task's gap.** The owner, on reflection:
   Issues are *"a meta/workbench type environment… a way for me to get 'issues' with my whole stack
   recorded. It's not per session todo type issues."* That is spec §5's own sentence — "about this
   machine and its own defects, never about product work" — sharpened, and it settles the boundary
   the first draft left mushy: `question` earns its own type precisely *because* shoehorning a task's
   open questions into `issue` would erode the boundary just drawn. See §4b.
3. **Identity binds to the connection, not to every call.** The first draft's tools all took a
   `thread` parameter — token bloat, and the misdirection footgun: one wrong id banks knowledge onto
   the wrong thread silently and forever. Thread + author now bind at register, from the env the
   arbiter set. See §2a.
4. **The build order is inverted: channel before vocabulary.** The first draft built every new type
   up front, before anything could write them — tables ahead of their acceptance test, the discipline
   §5 of the spec applies to `issue` ("a table no session reads must not exist") ignored at birth.
   `post_message`, `bank_fact`, `raise_issue`, `record_done`, `get_dossier` all work **today**, with
   zero migrations. The honest first slice is the channel over what exists. See §5.

The one-line headline stands: **funes exposes an MCP server — its sovereign channel to any agent — pi
reaches it through that channel plus a thin native extension, and skills teach pi the discipline.**

---

## 1 · What pi actually is (grounding, from the docs)

pi is an AI-agent toolkit: `pi-coding-agent` (interactive CLI), `pi-agent-core` (runtime, tool
invocation, state), `pi-ai` (multi-provider LLM), `pi-tui`, `pi-telemetry`. Its extension surface, which
this design targets:

- **Extensions** — TypeScript modules, `export default (pi: ExtensionAPI) => {}`:
  - `pi.registerTool({name, description, parameters /* TypeBox */, execute(id, params, signal, onUpdate, ctx)})` — LLM-callable tools.
  - `pi.on(event, handler)` — lifecycle hooks: `session_start`, `session_shutdown`, `before_agent_start`
    (inject messages / modify system prompt), `agent_start|end|settled`, `turn_start|end`, `tool_call`
    (can block), `tool_result` (can modify), `input`, `before_provider_request`, `after_provider_response`.
  - `pi.registerCommand(name, {handler})` — slash commands.
  - `ctx.ui.notify|confirm|select|input|custom|setStatus|setWidget` — TUI surfaces; `ctx.cwd`, `ctx.mode`,
    `ctx.sessionManager`, `ctx.isProjectTrusted()`.
  - Locations: `~/.pi/agent/extensions/*.ts` (global), `.pi/extensions/*.ts` (project, trust-gated).
    Config in `~/.pi/settings.json` (`extensions`, `packages: ["npm:…","git:…"]`). May carry
    `package.json` + `node_modules`.
- **Skills** — `SKILL.md` (YAML frontmatter: `name`, `description`, optional `allowed-tools`) +
  `scripts/`/`references/`/`assets/`. Locations `~/.pi/agent/skills/`, `.pi/skills/`, npm packages.
  Invoked `/skill:name`. Same shape as this harness's skills.
- **MCP** via `pi-mcp-adapter` (the popular adapter): reads `.mcp.json` /
  `~/.config/mcp/mcp.json` (precedence order), format `{"mcpServers": {name: {command,args} |
  {url,auth,bearerToken} | {socket}}}`. Stdio, HTTP/StreamableHTTP+SSE, and unix-socket transports.
  Default is a lazy `mcp` proxy tool (~200 tokens, on-demand discovery); `directTools: true | [names]`
  promotes chosen tools to first-class (~150–300 tokens each).

---

## 2 · The architecture — four parts

```
   pi (agent, in a tmux pane)                     funes (OTP app, shared SQLite + Bus)
   ┌───────────────────────────┐                  ┌───────────────────────────────────┐
   │ skills: coordinate-via-    │   MCP (.mcp.json)│  Funes.MCP server  ── Channel      │
   │   funes, bank-what-you-    │◄────────────────►│    (its sovereign channel)   Facts │
   │   learn, keep-todos …      │  post_message,   │                              Issues│
   │ funes pi-extension (TS):   │  bank_fact,      │  identity bound per connection;    │
   │   session_start→register   │  raise_issue,    │  every call bumps warmth (measured)│
   │   before_agent_start→brief │  record_done,    │  reads: in_scope / paged facts / … │
   │   setWidget→show state     │  get_dossier …   │                                    │
   └───────────────────────────┘                  └───────────────────────────────────┘
          ▲ env: FUNES_THREAD / FUNES_AUTHOR / FUNES_MCP_URL (token-bearing)
          └── set by aleph's arbiter at spawn (tmux new-session/send-keys)
```

### 2a · The funes MCP server — the channel (custom, Elixir-native)

The core bridge, and it is *exactly* funes' boundary philosophy realized: funes stays sovereign; agents
reach it **only over its channel**. An MCP server **is** that channel — and being MCP, it serves *any*
agent (pi today, another tomorrow), not a pi-specific API. It runs as part of funes' OTP app over a
**local HTTP/StreamableHTTP or unix-socket** endpoint (funes is already a long-running node with the DB
and Bus; a stdio-per-invocation server would not fit a shared substrate — an out-of-band write is
durable but invisible to the node-local Bus, so the reactive board would go blind to it).

**The trade this makes, stated so it cannot be discovered later:** routing writes through the OTP node
puts BEAM liveness in the agent's write path. That is the correct trade (the Bus is what makes the
board reactive), but its failure mode is governed by §4's write contract: **funes down ⇒ pi's tools
fail loudly, the agent reports it, and nothing is queued or spilled locally** — a client-side buffer is
the second log this design exists to remove.

**Identity is a property of the connection, never a parameter of a call.** At spawn the arbiter puts a
session token in `FUNES_MCP_URL` (or hands a per-session unix socket); `register` binds the connection
to its thread and author. After that, `post_message(body)` — not `post_message(thread, body)`. Smaller
tool schemas, and cross-thread misdirection becomes *unrepresentable* rather than merely discouraged.
The two deliberate exceptions are `open_thread`/`close_thread`, which are cross-thread by nature and
take explicit arguments.

Tool surface (the verbs, mapping to funes contexts; ⊕ marks a funes addition with its slice in §5):

| Tool | funes | axis |
|---|---|---|
| `register()` | claims `pane_ref`, binds thread+author, **supersedes any prior live session for (thread, agent)** | — |
| `post_message(body, reply_to?)` | `Channel.post/1` | chatter |
| `open_thread(title)` / `close_thread(thread)` | `Channel.open_thread`/`close_thread` | — |
| `bank_fact(kind, text, check_cmd?, from_message?)` | `Dossier.bank_fact/1` — see provenance rules below | **knows / believes** |
| `raise_issue(summary, evidence?)` | `Dossier.raise_issue/1` — the **stack's** tracker (§4b) | stack defects |
| `record_done(text, evidence)` | `Dossier.record_event/1`, kind `work_landed` | done |
| `get_dossier()` | `Board.in_scope/1` (grown counts, §2b) | read-back |
| `get_facts(page?)` / `get_messages(page?)` | paged context reads, behind the lazy proxy | read past the cap |
| ⊕ `add_todo(text)` / `complete_todo(id)` | `todo` (slice 3) | next / done |
| ⊕ `raise_question(text)` / `resolve_question(id, resolution?)` | `question` (slice 4) | **doesn't know** |

Core verbs are `directTools` (always first-class in pi's prompt); the long tail — the paged reads,
thread management — stays behind the proxy. Every write goes through funes' single-writer +
`Bus.announce` discipline (spec §4/§10) — the MCP server is a *caller of the contexts*, never a second
writer to the DB. **No mirror, one writer.**

**`bank_fact` carries the full §4 vocabulary, or the channel launders provenance.** The rules, encoded
in the tool rather than hoped for:

- `kind` is the existing closed set — `decision | constraint | learned`. Certainty is NOT a kind (§4a).
- `provenance` defaults to `derived` — an agent is never the owner.
- `stated` is reachable **only** via `from_message`: a reference to an operator-authored `message` row,
  from which the verbatim quote is taken. This makes the capture path mechanically honest — a stated
  fact *cites the message that states it* — and closes the one abuse the provenance ordering exists to
  prevent: an agent's paraphrase laundered into the owner's instruction.
- `check_cmd` rides along when the claim is reproducible. A finding with the command that re-runs it
  outranks the same finding without one, by the spec's own total order.

**Warmth is measured at the server, not self-reported.** Every authenticated tool call *arrives at
funes* — an observable act — so the server bumps the session's `last_active_at` on each call, with the
Switchboard's forward-only `touch` semantics. This replaces the first draft's `agent_settled →
heartbeat` hook, which was a record *describing* activity ("measure what happens, never ask the worker
to log it"). One less thing pi can forget, and the cockpit's `● live` stays honest for free.

### 2b · The funes pi-extension — the native niceties (custom, TS)

What MCP tools alone can't do, via `pi.on(...)`:

- **`session_start` → register.** Read `FUNES_THREAD` / `FUNES_AUTHOR` / `FUNES_MCP_URL` from env
  (set by the arbiter), call `register()` — which claims the `pane_ref` and ends any prior live
  session for this (thread, agent), so a crashed predecessor cannot linger as a wakeable zombie.
- **`before_agent_start` → brief from structured state.** Pull `get_dossier()` and inject it into the
  system prompt / first message. **This is aleph §3b's thesis realized**: the agent wakes already
  knowing its goal, todos, unknowns, and blockers — briefed from funes state, never from a raw
  transcript replay. Two rules on the rendering, both anti-laundering:
  - **Every claim shows its provenance.** A `derived` fact with no `check_cmd` is rendered *as* a
    hunch, never as flat truth — otherwise generation N's unchecked guess becomes generation N+1's
    received ground truth, and confidence inflates across re-briefs with no one lying at any step.
  - **The brief states its own staleness and its cuts.** "Last banked activity 40m ago; later work is
    unrecorded" (§6's rule: unrecorded time is *named* as unrecorded), and every capped section
    carries its count — which requires `Board.in_scope/1` to grow `more` counts on LEARNINGS and
    SHIPPED, as BLOCKERS already has. A cap with no count is the empty-world lie in miniature.
- **`ctx.ui.setWidget` → show funes state** (open todos, blockers) in pi's *own* footer, so a human
  driving pi directly sees the same dossier the cockpit shows.

The extension calls the funes MCP tools; it holds no state of its own. When funes is unreachable it
surfaces the failure and does nothing else — no retry queue, no spill file (§2a).

### 2c · Skills — the discipline (custom)

`SKILL.md` files that teach *when*, since tools alone don't create judgment:

- **`coordinate-via-funes`** — talk on your thread (`post_message`), don't work in the void; reply to
  the human by name. **This skill is load-bearing for session fungibility, not politeness** (§4c): the
  channel is the continuity mechanism, and an agent that narrates its judgment on its thread has
  already banked most of what a successor needs.
- **`bank-what-you-learn`** — a reproducible finding is a fact *with its `check_cmd`*; a hunch is a
  derived fact *without* one, and the dossier will rank and render it as such; a gap is a `question`
  (once slice 4 lands; a message until then). Never dress a guess in a check it doesn't have — and
  before building on someone else's unchecked derived fact, re-verify it.
- **`keep-todos-current`** — `add_todo` as you plan, `complete_todo` as you finish; `record_done` with
  evidence for what shipped.
- **`report-done`** — close the loop: what shipped (with the command or commit that proves it), what's
  still open.

### 2d · Session bootstrap — the arbiter's job

When aleph's `Funes.Arbiter` (tmux backend) spawns a pane for a thread (design §5), it sets the env the
extension reads: `FUNES_THREAD=<id>`, `FUNES_AUTHOR=<agent>`, `FUNES_MCP_URL=<token-bearing endpoint>`,
and ensures a `.pi/mcp.json` (or user-global `~/.config/mcp/mcp.json`) points pi at the funes server.
This is the same `send-keys`/`new-session` seam the arbiter already owns — identity travels *in the
spawn*, so pi comes up already a citizen of its thread. **For the first slices the human is the
arbiter**: hand-export the env in a hand-spawned pane. Automation is the last slice, not a
prerequisite (§5).

---

## 3 · Custom vs. off-the-shelf (the owner's "some but not all")

- **Custom** (funes-shaped, we build): the funes **MCP server** (§2a), the funes **pi-extension** (§2b),
  the funes **skills** (§2c), the **arbiter bootstrap** (§2d).
- **Off-the-shelf** (install from `pi.dev/packages`): `pi-mcp-adapter` (connect the server) — the one
  hard dependency; plus general capability as desired — `pi-web-access` (fetch/search/PDF),
  `pi-lens`/`pi-readseek` (code feedback/navigation), `bigpowers` (engineering-method skills). We do
  **not** adopt the marketplace *memory* packages (`pi-hermes-memory`, `pi-memory`): they are
  single-agent scratchpads; funes is the **shared** coordination memory, and two memories answering the
  same question is exactly the drift the spec forbids.

---

## 4 · The knowledge model, corrected against the schema that exists

The Addendum (§C of the chat/env-layout doc) drafted the model from its prose — "facts, opinions,
unknowns" — and the review's central finding is that it should have been drafted from the `fact` table,
which already encodes most of it. This section is the corrected model; the Addendum carries a dated
pointer here.

### 4a · The certainty axis already exists — it is a query, not a type

Spec §4's total order **is** the certainty axis:

> `stated` > `derived` WITH a check > `derived` WITHOUT a check

and its own text names the last set "our unverifiable opinions." So, with **zero migrations**:

- **Knows** — `stated` facts, and `derived` facts carrying a `check_cmd` (rendered with the check, so
  a reader can re-run the claim).
- **Believes / opinions** — `provenance = 'derived' AND check_cmd IS NULL`. The dossier's OPINIONS
  section is *that query*. Confidence, where a surface wants it, is the **read-time rank rendered as
  words** — never a stored number, which would be an invented figure ("never invent a duration"'s
  cousin) that nothing ever updates ("a field computed at write time is not a fact at read time").
- **Hardening** — an opinion hardens by *gaining its `check_cmd`* (the claim is unchanged; its
  reproducibility axis fills in — the same living-field precedent as `taught`, which starts NULL and
  is stamped later), or by the owner stating it (a `stated` fact that `supersedes` the derived one).
- **Refutation** — a new fact with `supersedes` pointing at the old. The mechanism exists;
  `always_loaded_constraints` already honors it.

Rejected from the first draft, with reasons (see also §6): `kind: :opinion` (a second dimension inside
a discriminator — the exact move §4 already rejected for attribution; and `kind` classifies *what kind
of claim*, which is orthogonal to how surely it is held) and a stored `confidence` float (an
uncalibrated self-reported number that decays silently).

### 4b · Three kinds of "open", three homes

Settled by the owner's clarification, which is spec §5's "deliberately local" sentence sharpened:

| Thing | What it is | Home |
|---|---|---|
| **Stack defect** | "the termbox NIF crashes on resize" — a defect in the harness/machine itself | **`issue`** (exists). `thread_id` means *discovery site*, not ownership. The meta/workbench tracker. |
| **Task question** | "does raxol support embedding?" — a knowledge gap in the work itself | **`question`** ⊕ (slice 4). Thread-scoped; `state` open/resolved with a `resolved_at` from birth (the `closed_at` gap already recorded against `issue` must not recur); resolvable into a fact. |
| **Plan step** | "wire the composer to Channel.post" | **`todo`** ⊕ (slice 3). Thread-scoped; `done_at` NULL = open; order is insertion order (`id`), no order column — reordering is a later verb if evidence demands it. |

`question` earns a table *because* `issue`'s identity is now firm: folding a task's open questions into
the stack's tracker would erode the boundary the same day it was drawn. The migration comment records
this distinction and the confusion that paid for it. The dossier's BLOCKERS stays
`open_issues_for_thread` — stack defects discovered here or blocking this work; an agent's "I'm stuck
waiting on the human" is a `question` or a message, never an `issue`.

**Derived, never stored:**

- **NEXT** is the first open todo. A stored `next` is a second answer to ordering — cut.
- **DOING** is a *warm live session* ∧ the first open todo. A stored in-progress marker is exactly the
  mirrored liveness state §2 bans — a dead session's stale "doing" flag lies indefinitely. Cut.
- **DONE** is a **merged view**: todos by their own `done_at`, plus `work_landed` events for outcomes
  that were never planned as todos — the spec's amended-§4 pattern (merge rows by their own
  timestamps, never copy). `complete_todo` never emits an event; `record_done` is for judgement-worthy
  outcomes and **takes evidence** (the command run, the commit) — "a claim that something works is
  backed by having run it" applies most of all to agents reporting completion.
- **EVIDENCE** as a type from the first draft is cut entirely: it was never defined, and
  `fact.check_cmd`, `fact.incident`, and `issue.evidence` already exist. Undefined vocabulary is a
  dumping ground pre-ordered.
- **GOAL / NORTH STAR** stays `thread.title`, as `Board.in_scope` already derives it. The first
  draft's `set_north_star` would have made two answers to "what is this thread for" — cut; renaming a
  thread is a thread verb if ever wanted.

### 4c · Fungible sessions — the principle, and what actually breaks it

The principle stands: sessions are disposable; the thread's funes state is the only durable truth;
crossing a compaction/context boundary = re-brief a fresh session from funes. Three breaks, each with
its mitigation designed in rather than discovered:

1. **The unbanked tail.** Work done since the last bank/post is *gone* across a re-brief — and the
   successor doesn't know what it doesn't know. No shutdown-hook flush can fix this: the spec measured
   a pi `session_shutdown` synchronous write that **never ran** ("reconciliation cannot depend on a
   clean exit"). The honest mitigations: the brief states its own staleness (§2b); and the channel is
   the real continuity mechanism — `coordinate-via-funes` is load-bearing (§2c). Disposability is
   *earned by banking*, not declared.
2. **The zombie race.** A crashed pi leaves `ended_at IS NULL`; spawn a replacement and
   `Switchboard.recipients/1` will wake *both* panes while the old one is warm. Two guards:
   `register()` supersedes any prior live session for its (thread, agent) (§2a), and a **partial
   unique index** `ON session(thread_id, agent_id) WHERE ended_at IS NULL` makes the DB, not
   convention, hold the invariant — which is per (thread, **agent**): multiple agents' sessions on one
   thread are coworkers, a feature.
3. **The cold-thread strand.** The Switchboard rightly never wakes a cold session, leaving the message
   `:pending` — and the fungible model's own answer, *spawn fresh and re-brief*, is an arbiter
   behavior nothing yet implements. **Named as an open loop**, deliberately: it needs the automated
   arbiter (§2d, last slice). Until then a pending message on a cold thread waits for the human to
   open a session, which the cockpit's "Needs you" facet already surfaces.

---

## 5 · Build order (Track B; runs after the aleph UI, Track A) — inverted: channel first

Each slice lands with its writer *and* its reader in the same gated change; no table ships ahead of
the thing that reads it.

1. **`Funes.MCP` over the existing contexts** — zero vocabulary migrations. The server (local HTTP or
   socket), connection-bound identity, `register` with supersede semantics + the partial unique index
   (one small *guard* migration), measured warmth on every call, and the verbs that work today:
   `post_message`, `bank_fact` (full §4 vocabulary incl. `from_message`), `raise_issue`,
   `record_done`, `get_dossier`, the paged reads. `Board.in_scope` grows its `more` counts. Proven
   end-to-end: a real pi session (hand-spawned, hand-set env) posts, banks, and the cockpit's
   LEARNINGS / BLOCKERS / CHATTER fill from real work.
2. **The extension + the first two skills** — `session_start → register`,
   `before_agent_start → brief` (provenance-rendered, staleness-stated), the footer widget;
   `coordinate-via-funes` and `bank-what-you-learn`. The re-brief loop is now real: kill a session,
   spawn a fresh one, watch it come up knowing.
3. **The `todo` slice** — migration (`done_at` from birth), `add_todo`/`complete_todo`, the dossier's
   TODOS / NEXT (derived) / DONE (merged view), `keep-todos-current`. The activity axis, whole, in
   one gate.
4. **The `question` slice** — migration (`resolved_at` from birth), `raise_question` /
   `resolve_question`, the dossier's UNKNOWNS beside FACTS (knowing what you don't know is
   first-class). OPINIONS needs no slice at all — it is §4a's query, and lands wherever the dossier
   rendering does.
5. **The arbiter bootstrap** — env-in-spawn automated (§2d), wired to the `s` "open a session" verb
   from the chat design; this is also where the cold-thread strand (§4c.3) gets its answer.

Then, earned: capabilities/MCP-connected surfaced in the dossier (funes learns what tools a session
has); telemetry via `pi-telemetry`; other agents over the same MCP channel.

---

## 6 · Rejected / parked

Carried from the first draft:

- **A pi extension that writes the shared SQLite directly** — refused: it bypasses funes'
  single-writer + Bus-announce discipline (spec §4/§10), a second writer that would drift. The
  extension calls the channel; it never touches the store.
- **Marketplace memory packages as the memory** — refused (§3): funes is the shared memory; a
  per-agent scratchpad answering the same question is the mirror the spec was written against.
- **A pi-specific HTTP API instead of MCP** — rejected: MCP is the agent-agnostic channel, so the same
  funes serves any agent; a bespoke pi API would weld funes to one client.
- **Auto-banking everything via hooks** — parked: `tool_result → bank_fact` manufactures facts the
  agent didn't judge. Banking stays a deliberate act (a skill), with hooks only for briefing — and
  note the two subtler manufacture paths the review added: a brief that renders derived claims as
  flat truth (§2b's provenance rule exists to close it) and any stored DOING marker (§4b).

Added by the revision, each with the failure it prevents:

- **`kind: :opinion` on `fact`** — a second dimension inside a discriminator (the dumping-ground move
  §4 already rejected for attribution), and a second encoding of uncertainty beside
  `provenance` × `check_cmd` (two sources of truth).
- **A stored `confidence` number** — an invented, uncalibrated figure that nothing updates; certainty
  is the read-time rank, rendered as words (§4a).
- **`question` folded into `issue`** — rejected the *other* way once the owner fixed `issue`'s
  identity as the stack's tracker (§4b): the fold would erode a boundary the same day it was drawn.
- **A `next` type** — NEXT is the first open todo, derived; a stored next is a second answer to
  ordering.
- **An `evidence` type** — never defined; `check_cmd` / `incident` / `issue.evidence` already exist.
- **`set_north_star`** — two answers to "what is this thread for"; the title *is* the north star.
- **A heartbeat hook** — self-reported liveness; warmth is measured from tool calls arriving at the
  server (§2a).
- **Per-call `thread` parameters** — the misdirection footgun; identity binds to the connection at
  register (§2a).
- **A shutdown-hook bank flush** — measured dead: the synchronous `session_shutdown` write never ran.
- **A client-side spill queue when funes is down** — a second log; the write contract is fail loudly
  and surface it (§2a).
