# pi integration — the funes MCP channel, a pi extension, skills, and bootstrap

Written 2026-08-15, opening the **agent-side** of the stack. The prior docs built the **memory**
(`modules/funes/`) and the **face** (`modules/aleph/`); this one is about the **hands** — how **pi**
(the agent, `github.com/earendil-works/pi`) plugs into the harness so the dossier's facts / opinions /
unknowns / todos / done / next become *real writes from a working agent*, not an empty cache. It builds
on the knowledge model settled in `2026-08-15-aleph-chat-comms-and-env-layout-design.md` (Addendum §C):
a dossier with no agent feeding it is the "cache that reports an empty world is a lie" failure at the
top of the stack.

The one-line headline: **funes exposes an MCP server — its sovereign channel to any agent — pi reaches
it through that channel plus a thin native extension, and skills teach pi the discipline.**

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
   │ funes pi-extension (TS):   │  bank_fact/opinion│  reads: in_scope / roster / …     │
   │   session_start→register   │  raise_question, │                                    │
   │   before_agent_start→brief │  add_todo, done …│                                    │
   │   setWidget→show state     │                  │                                    │
   └───────────────────────────┘                  └───────────────────────────────────┘
          ▲ env: FUNES_THREAD / FUNES_AUTHOR / FUNES_MCP_URL
          └── set by aleph's arbiter at spawn (tmux new-session/send-keys)
```

### 2a · The funes MCP server — the channel (custom, Elixir-native)

The core bridge, and it is *exactly* funes' boundary philosophy realized: funes stays sovereign; agents
reach it **only over its channel**. An MCP server **is** that channel — and being MCP, it serves *any*
agent (pi today, another tomorrow), not a pi-specific API. It runs as part of funes' OTP app over a
**local HTTP/StreamableHTTP or unix-socket** endpoint (funes is already a long-running node with the DB
and Bus; a stdio-per-invocation server would not fit a shared substrate).

Tool surface (the verbs, mapping to existing/planned funes contexts):

| Tool | funes | knowledge axis |
|---|---|---|
| `post_message(thread, body, reply_to?)` | `Channel.post/1` | chatter |
| `open_thread(title)` / `close_thread(thread)` | `Channel.open_thread`/`close_thread` | — |
| `set_north_star(thread, text)` | dossier | GOAL |
| `bank_fact(thread, text, evidence?)` | `fact` | **knows** |
| `bank_opinion(thread, text, confidence)` | `fact{kind: :opinion, confidence}` *(new)* | **believes** |
| `raise_question(thread, text)` / `resolve_question(id, into)` | `question` *(new)* | **doesn't know** |
| `add_todo(thread, text)` / `complete_todo(id)` | `todo` *(new)* | next / done |
| `record_done(thread, text)` | event | done |
| `raise_blocker` / `resolve_blocker` | `issue` | blockers |
| `get_dossier(thread)` | `Board.in_scope/1` | read-back |

Core verbs are `directTools` (always first-class in pi's prompt); the long tail stays behind the proxy.
Every write still goes through funes' single-writer + `Bus.announce` discipline (spec §4/§10) — the MCP
server is a *caller of the contexts*, never a second writer to the DB. This is the load-bearing rule:
**no mirror, one writer.**

### 2b · The funes pi-extension — the native niceties (custom, TS)

What MCP tools alone can't do, via `pi.on(...)`:

- **`session_start` → register.** Read `FUNES_THREAD` / `FUNES_AUTHOR` / `FUNES_MCP_URL` from env
  (set by the arbiter), announce the session to funes (claim its `pane_ref`), set author identity.
- **`before_agent_start` → brief from structured state.** Pull `get_dossier(thread)` and inject it into
  the system prompt / first message. **This is aleph §3b's thesis realized**: the agent wakes already
  knowing its goal, todos, unknowns, and blockers — briefed from funes state, never from a raw
  transcript replay.
- **`agent_settled` / `tool_result` → heartbeat.** Optionally update the DOING marker / warmth so the
  cockpit's `● live` and "Needs you" facets stay honest without the agent thinking about it.
- **`ctx.ui.setWidget` → show funes state** (open todos, blockers) in pi's *own* footer, so a human
  driving pi directly sees the same dossier the cockpit shows.

The extension calls the funes MCP tools (or funes' endpoint directly); it holds no state of its own.

### 2c · Skills — the discipline (custom)

`SKILL.md` files that teach *when*, since tools alone don't create judgment:

- **`coordinate-via-funes`** — talk on your thread (`post_message`), don't work in the void; reply to the
  human by name.
- **`bank-what-you-learn`** — a certain finding is a `fact`; a hunch is an `opinion` with a confidence; a
  gap is a `question`. Never bank a guess as a fact.
- **`keep-todos-current`** — `add_todo` as you plan, `complete_todo` as you finish; `record_done` at the
  end.
- **`report-done`** — close the loop: what shipped, what's still open.

### 2d · Session bootstrap — the arbiter's job

When aleph's `Funes.Arbiter` (tmux backend) spawns a pane for a thread (design §5), it sets the env the
extension reads: `FUNES_THREAD=<id>`, `FUNES_AUTHOR=<agent>`, `FUNES_MCP_URL=<endpoint>`, and ensures a
`.pi/mcp.json` (or user-global `~/.config/mcp/mcp.json`) points pi at the funes server. This is the
same `send-keys`/`new-session` seam the arbiter already owns — identity travels *in the spawn*, so pi
comes up already a citizen of its thread.

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

## 4 · Why this is the same frontier as the knowledge model

The dossier's certainty axis (facts / opinions / unknowns) and activity axis (doing / done / next) need
**both** funes *types* to store them **and** pi *tools* to write them. So the build is one coherent
loop: **teach funes the vocabulary → expose it over MCP → teach pi to speak it → watch the dossier fill
from real work.** The proof is the same "verified by eye" as the read-only board: drive a pi session on
a thread, and the cockpit's TODOS / OPINIONS / UNKNOWNS grow because pi banked them.

---

## 5 · Build order (Track B; runs after the aleph UI, Track A)

1. **funes knowledge-model types** — `todo`, `next`, `evidence`; then the certainty axis (`kind` +
   `confidence` on facts, a `question`/`unknown` type). Migrations + the green gate; `in_scope` grows to
   compose them. (This is Addendum §C's funes-later, now scheduled.)
2. **`Funes.MCP` server** — the channel (§2a): the core verbs over the contexts, local HTTP or socket,
   `directTools` for the core set. Proven with an MCP client (or pi) end-to-end.
3. **The funes pi-extension** (§2b) — `session_start` register + `before_agent_start` brief first (the
   highest-value hook), then the widget/heartbeat.
4. **The skills** (§2c) — the discipline, tested by running a real pi session and watching the dossier.
5. **The arbiter bootstrap** (§2d) — env-in-spawn, wiring it to the `s` "open a session" verb from the
   chat design.

Then, earned: capabilities/MCP-connected surfaced in the dossier (funes learns what tools a session
has); telemetry via `pi-telemetry`; the medium/other agents over the same MCP channel.

---

## 6 · Rejected / parked

- **A pi extension that writes the shared SQLite directly** — refused: it bypasses funes' single-writer
  + Bus-announce discipline (spec §4/§10), a second writer that would drift. The extension calls the
  channel; it never touches the store.
- **Marketplace memory packages as the memory** — refused (§3): funes is the shared memory; a per-agent
  scratchpad answering the same question is the mirror the spec was written against.
- **A pi-specific HTTP API instead of MCP** — rejected: MCP is the agent-agnostic channel, so the same
  funes serves any agent; a bespoke pi API would weld funes to one client.
- **Auto-banking everything via hooks** — parked: tempting to `tool_result → bank_fact` automatically,
  but that manufactures facts the agent didn't judge. Banking stays a deliberate act (a skill), with
  hooks only for liveness/briefing, not for inventing knowledge.
