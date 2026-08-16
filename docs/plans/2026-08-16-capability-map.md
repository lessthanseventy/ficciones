# Capability surface map — who can do what, through which door

Written 2026-08-16, to answer a recurring question directly: *do we have the right
capabilities in the right place for everyone?* This is a **living tracker**, not a one-shot
design — tick items as they land, add rows as new capabilities appear.

## Where we're trying to get

One machine where **funes is the shared truth**, and every actor — the human, Claude Code,
and the pi-borne agents — reaches it **through the surface natural to that actor**, with no
capability stranded in one surface that a peer needs too. The whole thing **reproduces from
the flake** on the next box, and nothing is a second source of truth. This map exists to
make the *gaps* to that state explicit so we fill them deliberately instead of discovering
them.

Two rules govern the whole map:

- **Parity across surfaces.** funes is reachable by agents over **MCP**, and by the human +
  Claude Code over **mise** (their "MCP"). Claude Code *also* gets its own MCP adapter. A
  capability that lives in one surface but not its peers is a **gap** unless there's a
  stated reason. (Reason that recurs: *aleph* is the human's rich read/write surface, so
  some human capabilities live there, not in a mise task — see the anti-sprawl note.)
- **The execution boundary.** funes **never runs machine commands** — it can't assume
  `mise`/the toolchain or it stops being portable. Execution lives in the **hands** (the
  harness: pi's bash, Claude Code's Bash, `cap`). funes only ever **records** outcomes.

## The actors

| Actor | What it is | Reaches funes via | Its read surface |
|---|---|---|---|
| **Human** (Andrew) | participant + operator | **aleph** (post/read) + **mise** (operate) | aleph cockpit |
| **Claude Code** (me) | the implementer harness | **manos claude-code MCP adapter** + **mise** | the brief / mise output |
| **pi agents** (codex, glm, kimi, claude-via-pi) | worker harnesses | **manos pi MCP adapter** + skills | the injected brief |
| **aleph** | the face/cockpit | reads funes contexts in-node | *is* the surface |
| **arbiter** | spawns/pokes panes | (slice 5) | — |

Legend below: ✅ built · 🔜 planned slice · ⬜ gap.

## Surface 1 — funes MCP tools (agents; and Claude Code)

| Capability | State | Note |
|---|---|---|
| register (connection-bound identity) | ✅ | supersede + warmth |
| post_message / get_messages | ✅ | the channel |
| bank_fact (full provenance) | ✅ | stated only via `from_message` |
| raise_issue / record_done | ✅ | evidence is hand-typed today |
| get_dossier / get_facts | ✅ | + resources: dossier, constraints |
| **open_thread / close_thread** | ✅ | move #6: the two DELIBERATE cross-thread verbs (the sanctioned exception to "no tool takes a thread param") — open returns a new thread id, close closes by id |
| **add_todo / complete_todo** | ✅ | slice 3 (#4a): thread-scoped; complete refuses another thread's todo. Dossier gains TODOS/NEXT/DONE (DONE merges completed todos + `work_landed`, replacing the old SHIPPED-only view) |
| **raise_question / resolve_question** | ✅ | slice 4 (#4b): thread-scoped, `resolved_at` from birth; resolve refuses another thread's; dossier gains UNKNOWNS beside FACTS. Durable answers still `bank_fact`'d |
| **record_check(cmd, exit, tail)** | ✅ | move #5: measured evidence → `check_passed`/`check_failed` event (kind keyed on the exit code); agent runs (via cap), funes records. Dossier gains CHECKS |
| **roster / list_threads / read-other-thread** | ⬜ | cross-thread awareness; scope tightly (today only aleph sees this) |
| **mark_read / catch_up(since)** | ⬜ | unread on my thread |

## Surface 2 — mise tasks (human + Claude Code; "our MCP")

| Capability | State | Note |
|---|---|---|
| `check` / `funes:*` (test/check/setup/doctor/serve) | ✅ | the gate + the funes loop |
| **`funes:release` / `funes:restart` / `funes:console` / `funes:logs`** | ✅ | operate the always-up service: build the release, redeploy, remote-iex the live node, follow logs |
| `aleph:*`, `manos:pi:test`/`manos:pi:check`, `flake:check`, `home:switch` | ✅ | |
| `cap` / `cap:clean` | ✅ | run once, structured failure, swept |
| **`funes:spawn`** | ✅ | move #2: `bin/funes rpc Funes.MCP.Spawn.env` into the LIVE node → prints the export block; killed the iex incantation |
| **`funes:dossier`** | ✅ | render a thread's brief from the CLI (Board.in_scope → Brief), parity with get_dossier |
| **`funes:post`** | ✅ | post as the operator from the CLI, parity with post_message |
| **`funes:roster`** | ✅ | who's live (Staff.roster), warm/cold, from the CLI |
| **`funes:sql`** | ⬜ | `sqlite3` the db for the 2am path (doctor exists; this is raw) |
| **`funes:console`** | ✅ | remote iex into the *running* service node (`bin/funes remote`), to mint/inspect without a second node — the release's `env.sh` makes it reach the live node |

## Surface 3 — skills (agent discipline)

| Skill | State | Note |
|---|---|---|
| coordinate-via-funes | ✅ | talk on your thread = continuity |
| bank-what-you-learn | ✅ | provenance honestly |
| **keep-todos-current** | ✅ | slice 3: add_todo as you plan, complete_todo as you finish, record_done (evidence) for outcomes |
| **verify-with-evidence** | ✅ | run the real command via `cap`, then `record_check` (measured), then `record_done`/`raise_issue` — evidence stops being self-reported |
| **catch-up / re-brief** | ⬜ | how a fresh session re-orients from funes |

## Surface 4 — manos adapters (harness ↔ funes)

| Adapter | State | Note |
|---|---|---|
| **pi** | ✅ | extension (register + brief + footer) + skills + mcp.json, wired via home-manager |
| **claude-code** | ✅ | move #3: `modules/manos/claude-code/`. Two doors like pi — MCP tools via `type:http` + **`headersHelper`** (`funes-cli.sh token`, a FRESH token per connect, survives a funes restart) and the brief via a `SessionStart` hook. Both scoped to the session by `funes:claude`'s `--mcp-config`/`--settings` flags, so a plain `claude` is untouched (no `~/.claude` mutation, no home-manager wiring needed). `funes:claude [thread-id]` = fresh thread or join. Verified funes-side; the live `claude` MCP-connect is the human's smoke test. |

## Surface 5 — nix / env / services

| Piece | State | Note |
|---|---|---|
| pi packaged + on PATH | ✅ | byte-preserved bun binary |
| manos wired into pi declaratively | ✅ | mcp.json + settings.json merge |
| devShell / home profile | ✅ | |
| **funes as a home-manager/systemd USER SERVICE** | ✅ | move #1 done: a self-contained local `mix release` (`funes:release`) run headless by `systemd.user.services.funes`, loopback, real XDG db, migrate-on-boot, named node + cookie (via the release's `env.sh`) so `funes:console`/`:restart` reach the live node. The channel is *always up*. Verified end-to-end (release → migrate → serve → mint → MCP `initialize` 200) + `home-manager build`. |
| **funes release built BY NIX** (`nix build .#funes`) | ⬜ | move **A**, deferred: today the release is built locally by `funes:release` (repo-path service, like manos). Nix-packaging it (mix2nix incl. the exqlite NIF) is what reproduces on a bare next-box — do it when box #2 is real. |
| **aleph packaged** | ⬜ | the cockpit as a real app |
| **sandbox/cache-path allowlist** (Claude Code settings) | ⬜ | so npm/mise/pip installs+caches don't trip the sandbox and force retries |
| **NixOS pi wrapper** (byte-preserving ld-linux / nix-ld) | ⬜ | deferred with metal — a bun binary can't be patchelf'd |

## The parity lens (the sharpest view of the gaps)

Every funes capability should be reachable by *both* agents (MCP) and human+CC (mise). Where
it isn't, that's the work:

| Capability | agents (MCP) | human + CC (mise) | verdict |
|---|---|---|---|
| post to a thread | ✅ post_message | ✅ funes:post | **parity** |
| read a brief | ✅ get_dossier | ✅ funes:dossier | **parity** |
| start a session / hand out env | (register, in-adapter) | ✅ funes:spawn | **parity** (human-arbiter side) |
| who's live | ⬜ roster tool | ✅ funes:roster | now on our side; the agents' `roster` MCP tool is still a gap |
| open / close a thread | ✅ open_thread/close_thread | ⬜ funes:thread | agents ✅; a mise wrapper is the remaining thin bit |
| bank a fact | ✅ bank_fact | ⬜ funes:bank | maybe (human banks via aleph?) |
| run a check & record it | `cap` (run) + ✅ record_check | `cap` (run) + ✅ record_check | **run ✅, record ✅** (measured) |

**Anti-sprawl caution (the v1 failure):** the spec is emphatic that funes is *"not a set of
CLIs"* — v1 drowned in invented nouns and stale wrappers. So the mise parity pack stays
**thin and deliberate**: `funes:*` tasks are for *operate/script* access, not a re-creation
of the cockpit. The human's rich surface is **aleph**; mise is the shared *run-loop*, not a
second UI.

## Where this points — candidate next moves (not yet a commitment)

Grouped, with the dependency that matters:

1. ~~**funes-as-a-service.**~~ **✅ DONE (move #1).** The channel is now an always-up
   `systemd --user` service running a self-contained local `mix release` — headless,
   loopback, real XDG db, migrate-on-boot, named node + cookie. `funes:console` reaches the
   live node to mint/inspect. Nix-*building* the release (reproduce on a bare next-box) is
   split out as **move A**, deferred. Every other capability is now reachable against a
   channel that's actually up.
2. ~~**The mise parity pack.**~~ **✅ DONE (move #2).** `funes:spawn` (killed the iex
   incantation) + `funes:dossier` / `funes:post` / `funes:roster`, all thin wrappers over
   one `scripts/funes-cli.sh` that `bin/funes rpc`s the LIVE node. You + me now have
   first-class funes access from the shell. (Also fixed: the prod release logs at `:info`,
   not `:debug` — no per-query journal spam.) Still open here: `funes:sql` (raw sqlite3).
3. ~~**The claude-code manos adapter.**~~ **✅ DONE (move #3).** Claude Code is now a
   funes citizen like pi: `mise run funes:claude [thread-id]` opens/joins a thread and
   launches `claude` with the funes MCP tools (via `headersHelper`) + the brief hook
   scoped to that session. The **spawn-or-join primitive** (`Funes.MCP.Spawn.ensure/env/
   join/mint_for`) was backfilled to the `pi:*` launchers too, so `mise run pi:balanced
   [thread-id]` makes a pi model a citizen the same way — one path, both harnesses. Both
   degrade gracefully when the channel is down (launch plain).
4. ~~**Vocabulary slices** — todo (3), question (4).~~ **✅ DONE.** Both the activity axis
   (TODOS/NEXT/DONE) and the knowledge-gap axis (UNKNOWNS) are built, rendered in all three
   surfaces (funes brief, pi `brief.ts`, aleph cockpit), with `keep-todos-current`.
5. ~~**Measured verification**~~ **✅ DONE (move #5).** `record_check(cmd, exit, tail)` lands a
   `check_passed`/`check_failed` event (kind keyed on the exit code), the dossier gains a CHECKS
   pane (all three surfaces), and the `verify-with-evidence` skill makes an agent run the real
   command via `cap` and record the measured result — evidence stops being self-reported. (Still
   open here: re-running `fact.check_cmd` to confirm a stored fact still holds.)
6. ~~**open_thread / close_thread tools**~~ **✅ DONE** — the two deliberate cross-thread verbs.
7. **sandbox/cache allowlist** — small, anytime.
8. **arbiter** — the capstone, stays last.

The `cap` run-loop tooling (run once, structured failure, swept) is **done** and underlies
5.
