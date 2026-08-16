# manos — the hands

The third story in the stack. `funes` is the memory, `aleph` is the sight, `manos` is the
**hands**: how a working agent reaches funes, comes up already knowing its thread, and banks what it
learns as it works. Read `../funes/docs/spec.md` and
`../../docs/plans/2026-08-15-pi-integration-and-funes-mcp-design.md` before reshaping anything here —
this module is Track B's agent side, and the spec's boundaries govern it.

## What manos is, and is not

**manos is vendor-agnostic by identity.** funes' channel is MCP — an agent-agnostic protocol, not a
pi API — so *any* harness can be a citizen of a thread. manos holds **one adapter per harness**, each
a thin bridge from that harness's lifecycle to funes' one sovereign channel:

- **`pi/`** — the pi adapter (built). A TypeScript extension for `pi`
  (`github.com/earendil-works/pi`): register at session start, brief before the agent runs, show
  funes state in the footer. pi is the harness for codex / glm / kimi / any model that speaks it.
- **`claude-code/`** — *not built yet, and not scaffolded.* Claude (and Claude Code natively) is a
  first-class harness too; its adapter is born when it has content, never as an empty directory that
  lies about what exists (root `AGENTS.md`).

**The rules that hold across every adapter — break one and manos stops being the hands:**

- **An adapter is a client of funes' MCP channel, never a second writer.** It calls the channel; it
  never touches the shared SQLite. A direct write bypasses funes' single-writer + Bus-announce
  discipline (spec §4/§10) — the drift the whole stack is built against.
- **An adapter holds no state.** No retry queue, no spill file. When funes is unreachable it surfaces
  the failure and does nothing else — a client-side buffer is the second log this design removes
  (pi doc §2a).
- **No harness's specifics leak into another's.** A model, a provider, a harness are configuration
  (spec §8). The shared discipline lives in the skills (harness-neutral prose); only the lifecycle
  glue is per-adapter.
- **Identity rides the connection, never a call.** The token minted for a (thread, agent) is the whole
  identity. No adapter ever passes a `thread` parameter; misdirection is unrepresentable (pi doc §2a).
- **Briefing is honest or it launders.** A brief renders every claim with its provenance — a `derived`
  fact with no `check_cmd` reads AS a hunch, never as flat truth — and states its own staleness and
  its cuts, or generation N's guess becomes generation N+1's ground truth (pi doc §2b).

## The two doors, one token

An adapter reaches funes through **two MCP connections that share one bearer token**, and the token —
not the transport — is the identity:

1. **The extension's own client** calls `register` (once, at session start) and `get_dossier` (to
   brief), deterministically, before the model runs. There is no pi API to invoke a tool from a hook,
   so the extension is itself a small MCP client (`pi/src/mcp.ts`).
2. **`pi-mcp-adapter`** exposes funes' write verbs (`post_message`, `bank_fact`, `raise_issue`,
   `record_done`) to the *model* as first-class tools.

Because funes binds a session to the **token** (`Funes.MCP.Tokens.bind_session/2`), not to a transport
connection, `register` on door 1 claims the session that door 2's calls then resolve to — so the
model's writes bump the same session's warmth for free. Register once; both doors are that session.

## Install (the human is the arbiter, for now)

Slices before the automated arbiter (pi doc §5, slice 5) install by hand. In the serving funes node's
`iex`, `Funes.MCP.Spawn.env/2` opens a thread, staffs an agent, mints a token, and prints the
`export FUNES_*` block. Paste it into a fresh pi pane, then point pi at manos:

- `~/.pi/agent/settings.json` → `"extensions": [".../modules/manos/pi/src/extension.ts"]`,
  `"packages": ["pi-mcp-adapter"]`, `"skills": [".../modules/manos/skills/*"]`.
- an `.mcp.json` (see `pi/mcp.json.example`) points `pi-mcp-adapter` at
  `http://127.0.0.1:${FUNES_MCP_PORT}/mcp` with `Authorization: Bearer ${FUNES_TOKEN}`.

The env contract (`FUNES_MCP_URL` for the endpoint, `FUNES_TOKEN` for the bearer) splits the plan
doc's "token-bearing endpoint" honestly: funes authenticates with a header, not a URL.

## The dev loop

Driven through the shared mise tasks (`mise tasks`), same as the rest of the repo:

- `mise run manos:pi:test` — the pi adapter's unit suite (`bun test`) — the TDD loop for the brief renderer.
- `mise run manos:pi:check` — typecheck + tests, the precommit gate for this module.
- `mise run funes:serve` — boot funes with its sovereign channel on, against the scratch db, so a
  hand-spawned pi pane has something to register with.
- `mise run check` — the whole-repo gate (funes + aleph + pi).

## Verify

The proof of the re-brief loop is **seen, not asserted** (pi doc §5, slice 2): boot `funes:serve`,
hand-spawn a pi pane, watch it register and brief; kill it, spawn a fresh one, watch it come up
knowing. The pure renderer is unit-tested (`bun test`); the wiring is proven live.
