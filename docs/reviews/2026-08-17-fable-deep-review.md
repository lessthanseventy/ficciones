# Fable deep review — 2026-08-17

A fresh-eyes, adversarial pass over the whole stack (funes / aleph / manos / flake), with the
"every module is about to become a public API" lens: what would the owner want to change, and is
that a knob or a hardcode? Method: three adversarial review agents (funes, aleph, manos) + a
plugin-knob enumeration agent, every finding verified against the code before acting; fixes
landed on `fable-deep-review` as small green commits (main fast-forwardable); everything larger
is filed below and into the funes **fable deep review** thread (id 7 on the live service, 20
todos) — the queue the Tlön coworker starts chewing.

> **Do first after merging:** `mise run funes:restart`. The RUNNING release's `/mint` is broken
> (the Jason packaging bug, fixed here) — until the redeploy, no launcher can mint a token
> against the live channel. Then `mise run home:switch` for the flake changes.

**Verification discipline:** every fix ran its module gate (`funes:check` 213 · `aleph:check`
215 · all manos suites) and, where the flake was touched, `flake:check` + a `nix eval` of the
generated file. `home:switch` remains the human's — **run it after merging** (the flake changed:
resurrect allowlist, failover knobs, plugin-policy seeds). Gates that touch unix sockets
(`manos:lsp:check`) must run OUTSIDE the Claude sandbox — inside it they fail spuriously, same
artifact class as the phantom `/dev/null` dotfiles.

---

## 1 · What was FIXED (committed on this branch)

### Workstream B — tmux socket per coworker · `5419e76`
The Tlön coworker lived as a `tlon` session on the DEFAULT tmux server, where resurrect+continuum
restored torn-down coworkers stale and `@resurrect-processes` relaunched `pi` at reboot.
- Every coworker now runs on its **own tmux server** (`tmux -L aleph-<profile>`,
  `Aleph.Profiles.socket/1`) booted from a **persistence-free `tmux.conf`** that
  `Profiles.materialise!` writes into the profile dir (mouse, extended-keys csi-u, vi copy-mode,
  chrome-off, mode-style — no persistence plugins).
- All call-sites follow: `profile_launcher` (`-L` + `-f`), tab strip + tab click,
  `Stack.tlon_up?`, `mise aleph:run`/`aleph:reset` (reset kills the coworker server + sweeps a
  legacy default-server session).
- flake: agent harnesses (`pi`, `claude`, both mise wrappers) removed from
  `@resurrect-processes` — persistence still restores Andrew's own `iex/mix/nvim/vim` panes,
  never an agent (see Open decision 2).
- Verified end-to-end: the generated conf boots a real tmux server with the right options.

### Settings UI (Andrew's ask) · `0cbd447`
The coworker driver model is an **in-app, runtime knob**, not a compiled constant:
- `Aleph.Config` — `~/.config/aleph/config.json` (atomic writes; corrupt/absent file → compiled
  defaults win). `Profiles.fetch/1` merges the override, so it flows into the materialised
  `settings.json` AND the `--model` flag on next spawn.
- `m` (bare in Tlön / `^␣m` from the terminal) cycles a Claude-first ring:
  claude-sonnet-5 → claude-opus-4-8 → glm-5.2 → kimi-k2.7-code → deepseek-v4-pro.
- `Panel.Settings` on Tlön shows the effective driver, its provenance ("set here"), the ring
  with the current entry marked, and an honest "applies on respawn" note. StatusBar hints gain
  `^␣m driver`. Claude stays the default.

### Correctness fixes
| Sev | Where | Defect → fix | Commit |
|---|---|---|---|
| **HIGH (live)** | `Funes.MCP.Gateway`/`Tokens` | Called `Jason` without declaring it — present at dev/test only transitively (credo), so the prod release ships WITHOUT it: **`/mint` on the always-up service raises, every citizen launch against the live channel fails to auth**. Found live while opening the backlog thread. Fixed with the built-in `JSON` module (zero-dep discipline). **Redeploy needed: `mise run funes:restart`** — the first todo on the backlog thread. | `72c9436` |
| HIGH | `Aleph.Cockpit.crash_issue_open?` | Enumerated `open_issues_for_thread`'s `%{shown, more}` map as a list → raised → rescue swallowed it → **a crashed cockpit never filed its funes issue**. Reads `.shown` now, public + tested. | `20da6a0` |
| HIGH | `Funes.Message.post_changeset` | Secret scanner covered only `fact.text`; the channel — the PRIMARY capture path, FTS-searchable — stored bodies unscanned. Same slice-B guard now on `:body` (+ test). | `a05f02c` |
| CRITICAL | `Aleph.Cockpit.render/1` | Every render (≈125/sec while a coworker streams) re-ran the Tlön subprocess battery (git ×6, nix-env sweeps, df, tmux, 500ms TCP probe) — renders serialized, input starved. Probes now cached in state, refreshed ≤ every 2s on the tick, Tlön-only; `ahead_behind`/nix sweep deduped (each forked TWICE per read); funes probe timeout 500→150ms. | `f861c84` |
| HIGH | `Aleph.Terminal` | Default `:permanent` restart re-execed a crashed terminal's harness while `Sessions` monitored only the old pid — invisible orphan PTYs, duplicate coworkers. `restart: :temporary`. | `f861c84` |
| MED | `Aleph.Cockpit.machine_read` | Machine coworker find-or-SPAWNED inside the render hot path; a failing spawn re-materialised + re-ran `tmux new-session` per frame. Moved to a stateful preamble with 5s backoff. | `f861c84` |
| HIGH | `manos/pi` capture | No timeout on the capture fetch — one hung response wedged `capturing` forever (all capture dead, shutdown stalled). 30s AbortSignal default. | `5e344d5` |
| HIGH (security) | `manos/pi` capture | Raw transcript deltas egressed to ollama.com unredacted; funes' scan fires one hop too late. Outbound deltas now pass `redactSecrets` (mirrors `Funes.Secrets` patterns, tested); `captureModel` is a funes-recall.json knob (point it at the local daemon for zero egress). | `5e344d5` |
| MED | `manos/pi` capture | Watermark advanced before the await — a failed extraction permanently dropped that delta. Advances only after success now. | `5e344d5` |
| HIGH | `manos/lspd` client | Daemon outlives pi + didChange unadvertised → answered against first-open text forever. `openDoc` stats the file and didClose+didOpens on change. | `5e344d5` |
| MED | `manos/lspd` server | A corrupt frame killed the SHARED daemon (unguarded JSON.parse); listen errors crash-looped. Frame cap (16MiB) + per-connection drop + `server.on("error")` (+ tests). | `5e344d5` |
| MED | `manos/lsp` shim | Concurrent selfHeal spawned duplicate daemons racing unlink+listen → single-flight; shim now honors `MANOS_LSPD_SOCK` (override used to desync the rendezvous). | `5e344d5` |
| LOW | misc | `pos()` NaN fallback; `impact` rejects a `-`-prefixed git ref (option injection); footer dead condition; `Consult.create_ask` two-write → transaction; partial index on `message.consult_id`. | `5e344d5` / `a05f02c` |

### Config made intentional (workstream D) · `58f12fb` + `ea98142`
The enumeration found **pi-sandbox silently ACTIVE on baked-in defaults** (enabled=true with no
sandbox.json — contradicting the "not enabled today" memory) and **pi-permission-system
installed with the all-`ask` empty-config default**. Now explicit, seeded write-once (the files
are runtime-writable by their plugins, so no store symlinks):
- `sandbox.json` — Tlön-sandbox-modeled: unix sockets + local binding (manos-lspd, tmux),
  writes scoped to `~/projects` + caches, repo host allowlist, hard denyWrite on
  `.env`/`*.pem`/`*.key`, deny-`/home` read posture with carve-outs.
- pi-permission-system — allow-by-default with hard path-denies on credential files
  (`.env`, keys, `~/.ssh`, `~/.aws`, `auth.json`), `sudo *` asks.
- `interactive-shell.json` — `defer: true` (its large tool schema out of every prompt).
- unipi notify — `native.suppressWhenFocused: true`.
- provider-failover — `showUsage: true` (lean-on-Claude wants the cap readout visible), and the
  five cache/context knobs (`preserveInterruptedContext`, `routeCompactionToHealthyAccount`,
  `autoContinue`, `cooldownMs` 6h, `maxRecheckIntervalMs` 10min) declared at their defaults so
  upstream can't silently retune failover.
- `funes-recall.json` — gains `captureModel`.

## 2 · FILED, not built (the dogfood backlog — also in the funes thread)

**funes**
1. §4 write-contract retry-once is unimplemented: a SQLITE_BUSY past the 100ms busy_timeout
   RAISES out of `Repo.insert` (never `{:error, changeset}`), crashing the MCP tool call. Wrap
   the write contexts in retry-once. (MED — a named spec contract.)
2. Switchboard wake coalescing keys on `thread_id` and pokes only the first session — with two
   coworkers on one thread and a pane-keyed arbiter, the second is never woken though the row
   reads delivered. Coalesce by the arbiter's address unit. (MED — lands with the tmux backend.)
3. `chorus/1` windows the GLOBAL newest 300 messages; a busy board can render an active thread
   as empty and misrank it — "a cache that reports an empty world is a lie". Per-thread fetch
   (window function). (MED)
4. Wakes actuate synchronously in the switchboard GenServer (their own moduledoc flags it) —
   supervised Task per poke before any blocking backend. (MED)
5. `Presence.clock_out/in` non-atomic app-env read-modify-write (LOW); `Register` tool
   hard-matches the session insert — add `unique_constraint` + tool error (LOW); cold-thread
   autonomous spawn runs on the live path only, not on drain — decide the asymmetry (LOW).
6. Knob pass: dossier caps (5×4), chorus 300/20, `recent_*` limits, spawn defaults,
   `Secrets.@patterns` extensibility → `Application.get_env` with docs.

**aleph**
7. Split "repaint terminal cells" from "reload funes reads" — probe caching landed, but a
   coalesced `:render` still re-runs chorus/roster/dossier DB reads per frame. (MED)
8. Narrow-layout PTY sized with wide-column geometry below 80 cols (LOW); machine coworker is
   registered under `:machine` so the arbiter can't wake it by thread id — decide intent (LOW).
9. Missing tests: a Sessions crash/registry-desync test (would have caught the `:permanent`
   orphan), a file_crash_issue integration test (would have caught the headline shape bug).
10. Knob pass: `@tick_ms`/`@probe_ms`/coalesce, `@repo` hardcode in Profiles, Health panel
    thresholds (disk/mem 90, load 4.0), panel caps (30/10/5), `4040` literal.
11. Workstream C build-out (design: `docs/plans/2026-08-17-coworker-surfaces-design.md`):
    Sessions coworkers through profiles ("project" profile), a `harness` dimension
    (claude-code coworkers), a Support Desk space, the Comms wake affordance, settings-panel
    growth (thinking level, per-space profile picker), and a "respawn coworker now" verb after
    a model change.

**manos**
12. Verify the funes-brief capture filter against the LIVE entry shape (`<funes-brief` vs
    `# Brief:` — if pi surfaces raw content, every capture re-ingests the brief); consult has
    no brief filter at all. (Needs a live session — verify, then fix.)
13. Correction detector fires on ordinary imperatives ("don't forget the migration") — tighten
    to preference-shaped structure or make opt-in; dedup is exact-last-string only.
14. Consult `KNOWN_MODELS`/DEFAULT_MODEL duplicated from the flake's model catalog —
    single-source. lspd: daemon-side exclusive lock before listen; unit tests for `#onData`
    framing + the server-request ack path (the documented Expert-wedge fix is untested).
15. Knob pass: timeouts (LSP 15s, shim 20s), `MAX_DELTA_CHARS`, `max_tokens`, correction
    MIN/MAX, `OPERATOR`, reload delay, brief thresholds.

**plugins**
16. Wire notify's `permission_request` event on (via `/unipi:notify-settings`) now that
    pi-permission-system has a real policy; set `PI_RESEARCH_MODEL` to a cheap/local model so
    `/research` never burns the driver's bucket; `agent_browser_web_search` is a dead tool slot
    (no Exa/Brave key) — leave off or remove.

## 3 · Open decisions for Andrew

1. **Claude-via-pi billing** (chief). The Tlön coworker drives `anthropic/claude-sonnet-5`
   through pi-multi-account's OAuth; pi warns this may bill as per-token EXTRA usage rather
   than the $100 plan. Watch one cycle (or the console usage page); the SETTINGS `m` verb makes
   glm-first one keystroke if it's metered. Claude stays default meanwhile.
2. **Resurrect scope.** `claude` + `mise run funes:claude` were dropped from
   `@resurrect-processes` along with `pi` — auto-relaunching ANY agent at restore burns budget
   with no human in the loop. Re-add the claude entries if you want those panes auto-restored.
3. **pi-sandbox + permission policy now explicit.** Behavior changes at the next `home:switch`:
   the sandbox allowlist replaces the plugin's baked-in defaults (which were silently active),
   and the permission layer goes allow-with-credential-denies instead of all-`ask`. Both files
   are seed-once — your runtime grants persist; review the seeds if the posture feels off.
4. **Settings apply-on-respawn.** `m` persists but doesn't bounce the running coworker —
   killing a coworker mid-work is a decision, not a default. A "respawn now" verb is filed.

## 4 · The knob ledger

The full per-plugin option tables (defaults, current values, semantics — pi-sandbox,
pi-permission-system, pi-multi-account's ~25 keys, pi-research's env matrix, interactive-shell,
notify, mcp-adapter, retry, cc-header, web-search, agent-browser) live in the enumeration
agent's report; the actionable subset landed in §1/§2. Elixir-side magic-constant inventory:
funes is disciplined (most timing/caps already config or named functions; loose ends are the
chorus `300` and search snippet `12`); aleph's are listed in item 10. One trap confirmed while
tuning: `Stack.funes_up?`'s hardcoded `4040` is CORRECT (it probes the systemd service, not
aleph's own 4041 world) — a naive "read `:mcp_port`" cleanup would silently break the health
check; it's now commented in place.
