# manos/lsp as a supervised sidecar — design

_2026-08-17. Status: designed, not yet built. Brainstormed from a dogfooding session where
Expert (the Elixir LSP) cold-indexed and re-rolled a flaky startup crash on every pi start._

## Why

manos/lsp today is an in-process pi extension: the `LspClient` pool (Expert, tsserver, nil,
bash-ls, json-ls) lives inside the pi process and dies with it. Two costs fall out of that, and
both bite the dogfood loop:

1. **Expert cold-indexes on every pi start.** A fresh pi (relaunch, or now a [[manos/reload]]
   respawn) re-spawns Expert, which re-indexes the project and re-rolls its intermittent
   `no_translation` startup crash (see the 2026-08-17 manos/lsp framing fix, commit cb87cb6).
2. **Iterating on LSP tool code needs a full pi restart** — pi loads its extensions once, at
   startup, so a change to `client.ts`/`adapters.ts` isn't live until pi restarts.

`reload` (commit ddb53bf) makes the pi restart cheap (respawn + `--continue`), but it doesn't make
Expert warm — a respawn still cold-starts it. The sidecar fixes the root: **move the Expert pool
and the tool logic out of pi into a long-lived process; pi keeps only a connection.**

This is not a new pattern here — funes (the always-up MCP service on :4040/:4041), ollama, and
aleph's embedded terminals are all supervised long-lived processes. manos/lsp is simply the one
in-process tool that outgrew its lane by accidentally holding heavy subprocess state.

## Goals (both, tiered)

- **A — warm Expert across pi restarts.** The everyday win: a pi restart leaves Expert warm, so
  LSP tools are instant and the flaky startup crash is paid at most once per _daemon_ life, not
  per _pi_ life. Needs nothing fancy — just that the daemon outlives pi.
- **B — iterate on tool code without restarting pi.** Editing daemon code restarts the _daemon_
  (not pi), so pi never loses context.
- **B-full (stretch) — warm Expert even across code edits.** A hand-rolled "reload-handlers"
  seam that re-imports tool modules while keeping the Expert pool alive. Only if B's daemon
  cold-start proves annoying. (`bun --hot` was evaluated and does NOT give this for free — it is
  module-graph HMR needing explicit `import.meta.hot.accept` wiring, verified 2026-08-17; a bare
  `bun --hot entry.ts` did not re-execute on edit.)

## Decision: thin shim + Unix-socket daemon (not MCP)

Two shapes were weighed for the pi↔sidecar connection:

- **Chosen — thin in-process shim + Unix-socket daemon.** A tiny, stable pi extension declares the
  5 tools natively (`hover`/`symbols`/…, identical names + schemas) and forwards each call over a
  local socket to the daemon. Keeps pi's native tool UX the models already know; trivial protocol;
  no dependency on pi-mcp-adapter's (unverified) live tool-refresh behaviour; the shim almost never
  changes, so it rarely needs a pi reload.
- **Rejected for v1 — MCP server (funes pattern).** Reuses funes' wiring and puts the whole tool
  surface in the sidecar, but reshapes LSP tools into MCP tools, adds a hop, and leans on
  pi-mcp-adapter refreshing tools on reconnect (couldn't confirm; the adapter is compiled into the
  pi binary). funes already owns the MCP lane for data/collab; LSP is local, hot-path, and native.

## Architecture

```
  pi process                          manos-lspd (long-lived, supervised)
  ┌───────────────────┐   Unix socket ┌──────────────────────────────────┐
  │ manos/lsp shim    │──────────────▶│ request router                   │
  │  registerTool ×5  │  len-prefixed │  LspClient pool (client.ts)       │
  │  → socket forward │◀──────────────│   ├─ elixir:/…/aleph  → Expert    │  ← warm
  └───────────────────┘   {id,ok,text}│   ├─ elixir:/…/funes  → Expert    │  ← warm
                                       │   └─ typescript:/…    → tsserver  │
                                       └──────────────────────────────────┘
```

- **`manos-lspd`** (new package `modules/manos/lspd`) — owns today's `client.ts` (Expert pool,
  byte-exact `frameMessage`, evict-on-timeout) and `adapters.ts`, moved wholesale. Listens on
  `$XDG_RUNTIME_DIR/manos-lspd.sock` (fallback `~/.pi/manos-lspd.sock`). One daemon, N warm servers
  keyed by `(adapter, root)` — exactly today's `clients` Map, just hoisted behind a socket.
- **`manos/lsp` shim** (the existing package, shrunk) — registers the same 5 tools with identical
  names/schemas, so models see zero change. Each `execute()` opens/reuses a socket connection,
  sends `{id, method, params}`, returns the reply as a `ToolResult`. A per-request timeout in the
  shim (mirrors today's 15s) means a hung daemon errors rather than hanging pi.

## Protocol

Length-prefixed JSON over the Unix socket, one message per tool op — the same five operations the
tools already expose:

- request: `{ id, method: "hover"|"definition"|"references"|"symbols"|"diagnostics", params: { path, line?, col? } }`
- response: `{ id, ok: true, text }` or `{ id, ok: false, error }`

A pure `encode`/`decode` seam is the unit-tested boundary (like `frameMessage` is today). No auth,
no multiplexing scheme beyond `id` correlation — single user, local socket, filesystem perms.

## Supervision & lifecycle

- **systemd `--user` service** running the daemon, mirroring `funes:release`. mise tasks:
  `lspd:release` / `lspd:restart` / `lspd:logs` (and `lspd:console` if useful).
- **Daemon runs under `bun --watch`** — editing daemon code restarts the daemon (Expert cold once),
  pi untouched. (B-full stretch would replace this with the reload-handlers seam.)
- **Shim self-heal** — if the socket is dead on a tool call, the shim auto-spawns the daemon
  (detached) and retries once, so a fresh box / stopped service still works without ceremony. The
  systemd unit is the normal path; autospawn is the backstop.

## Error handling

- Socket dead → shim autospawns + retries once → else a clear "lspd unavailable — `mise run
  lspd:restart`" error.
- The Expert-specific hardening we already shipped (byte-exact framing, evict-on-timeout, the
  server→client request ack) **moves into the daemon unchanged** — the fixes come along for the ride.
- Daemon crash → systemd restarts it; in-flight requests fail fast (the shim's per-request timeout),
  the model retries, Expert re-indexes once.

## Testing

- Pure seams stay unit-tested and move with the code: adapter routing, `frameMessage`, and the new
  socket `encode`/`decode`.
- New daemon integration test: start `manos-lspd` on a temp socket, send a `symbols` request for a
  fixture `.ex`, assert the response. Gated by `mise run manos:lspd:check`, added to the `check`
  aggregate.
- End-to-end remains a live dogfood: warm-Expert is proven by restarting pi and seeing an instant
  `symbols` (no cold index), inspectable in `.expert/expert.log`.

## Scope / YAGNI

- **v1 = LSP only.** No MCP, no auth, no multi-client protocol, no sidecar "framework."
- **fmt-fold = fast-follow.** manos/fmt shells `mix format` per save (a ~1–2s BEAM boot on the hot
  path). Expert exposes `textDocument/formatting`, so fmt can become "ask the warm daemon to
  format" — one warm process kills both the cold-index pain and the per-save boot pain. Verify
  Expert advertises `documentFormattingProvider` first. Deferred until the sidecar is proven.
- **Other manos tools stay in-process.** consult (an API call), reload (a respawn), the pi brief
  renderer (a string render) hold no expensive warm state — sidecar-ing them is pure overhead.

## Rollout

1. New `modules/manos/lspd` package: move `client.ts` + `adapters.ts` in; add the socket server +
   codec. Shrink `modules/manos/lsp` to the forwarding shim (same tool names/schemas).
2. systemd `--user` unit + `lspd:*` mise tasks; wire the shim's socket path.
3. `home:switch` installs the unit; the daemon is independent of aleph, so no cockpit reboot needed.
   The shim change ships with the same pi settings pi already loads.
4. Prove warm-Expert live; then consider fmt-fold and, only if needed, the B-full reload-handlers
   seam.

## Risks / open questions

- **Socket path portability** — `$XDG_RUNTIME_DIR` vs a fixed `~/.pi/` path; pick one, document it.
- **`bun --watch` restart racing an in-flight request** — acceptable (request fails fast, retried);
  note it rather than engineer around it.
- **B-full** (warm across code edits) is unproven — it's a stretch, not a promise. Bare `bun --hot`
  does not deliver it; a hand-rolled module re-import is the likely path if we pursue it.
