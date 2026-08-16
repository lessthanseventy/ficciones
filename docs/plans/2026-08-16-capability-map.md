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
| **open_thread / close_thread** | ⬜ | designed as the deliberate cross-thread tools; never built |
| **add_todo / complete_todo** | 🔜 | slice 3 |
| **raise_question / resolve_question** | 🔜 | slice 4 |
| **record_check(cmd, exit, tail)** | ⬜ | measured evidence → `check_passed`/`check_failed` event; agent runs (via cap), funes records |
| **roster / list_threads / read-other-thread** | ⬜ | cross-thread awareness; scope tightly (today only aleph sees this) |
| **mark_read / catch_up(since)** | ⬜ | unread on my thread |

## Surface 2 — mise tasks (human + Claude Code; "our MCP")

| Capability | State | Note |
|---|---|---|
| `check` / `funes:*` (test/check/setup/doctor/serve) | ✅ | the gate + the funes loop |
| `aleph:*`, `pi:test`/`pi:check`, `flake:check`, `home:switch` | ✅ | |
| `cap` / `cap:clean` | ✅ | run once, structured failure, swept |
| **`funes:spawn`** | ⬜ | wrap `Funes.MCP.Spawn.env` — today an **iex incantation**; should be one task |
| **`funes:dossier` / `funes:brief`** | ⬜ | read a thread's brief from the CLI (parity with get_dossier) |
| **`funes:post`** | ⬜ | post as a participant from the CLI (parity with post_message) |
| **`funes:roster`** | ⬜ | who's live (Staff.roster) from the CLI |
| **`funes:sql`** | ⬜ | `sqlite3` the db for the 2am path (doctor exists; this is raw) |
| **`funes:console`** | ⬜ | remote iex into the *running* serve node, to mint/inspect without a second node |

## Surface 3 — skills (agent discipline)

| Skill | State | Note |
|---|---|---|
| coordinate-via-funes | ✅ | talk on your thread = continuity |
| bank-what-you-learn | ✅ | provenance honestly |
| **keep-todos-current** | 🔜 | slice 3 |
| **report-done / verify** | ⬜ | run the real command via `cap`, then `record_done`/`raise_issue` with the measured output — evidence stops being self-reported |
| **catch-up / re-brief** | ⬜ | how a fresh session re-orients from funes |

## Surface 4 — manos adapters (harness ↔ funes)

| Adapter | State | Note |
|---|---|---|
| **pi** | ✅ | extension (register + brief + footer) + skills + mcp.json, wired via home-manager |
| **claude-code** | ⬜ | **confirmed wanted**: Claude Code reaches funes via its own MCP adapter (settings `mcpServers`) **and** mise. Likely also a SessionStart brief hook + the shared skills. This is the deferred `modules/manos/claude-code/`. |

## Surface 5 — nix / env / services

| Piece | State | Note |
|---|---|---|
| pi packaged + on PATH | ✅ | byte-preserved bun binary |
| manos wired into pi declaratively | ✅ | mcp.json + settings.json merge |
| devShell / home profile | ✅ | |
| **funes as a mix-release + a home-manager/systemd USER SERVICE** | ⬜ | **high leverage**: `funes:serve` is a hand-run iex today — nothing can register if no one babysat a terminal. A managed service means the channel is *always up*. |
| **aleph packaged** | ⬜ | the cockpit as a real app |
| **sandbox/cache-path allowlist** (Claude Code settings) | ⬜ | so npm/mise/pip installs+caches don't trip the sandbox and force retries |
| **NixOS pi wrapper** (byte-preserving ld-linux / nix-ld) | ⬜ | deferred with metal — a bun binary can't be patchelf'd |

## The parity lens (the sharpest view of the gaps)

Every funes capability should be reachable by *both* agents (MCP) and human+CC (mise). Where
it isn't, that's the work:

| Capability | agents (MCP) | human + CC (mise) | verdict |
|---|---|---|---|
| post to a thread | ✅ post_message | ⬜ funes:post | thin on our side |
| read a brief | ✅ get_dossier | ⬜ funes:dossier | thin on our side |
| start a session / hand out env | (register, in-adapter) | ⬜ funes:spawn (iex today) | thin **both** |
| who's live | ⬜ roster tool | ⬜ funes:roster | only aleph has it |
| open / close a thread | ⬜ tools | ⬜ funes:thread | thin **both** |
| bank a fact | ✅ bank_fact | ⬜ funes:bank | maybe (human banks via aleph?) |
| run a check & record it | harness bash + `cap` (run) / ⬜ record_check | `cap` (run) / ⬜ record | run ✅, record ⬜ |

**Anti-sprawl caution (the v1 failure):** the spec is emphatic that funes is *"not a set of
CLIs"* — v1 drowned in invented nouns and stale wrappers. So the mise parity pack stays
**thin and deliberate**: `funes:*` tasks are for *operate/script* access, not a re-creation
of the cockpit. The human's rich surface is **aleph**; mise is the shared *run-loop*, not a
second UI.

## Where this points — candidate next moves (not yet a commitment)

Grouped, with the dependency that matters:

1. **funes-as-a-service (nix).** Highest leverage and arguably first: nothing registers or
   briefs if the channel isn't up, and today that's a hand-run iex. A managed user service
   makes every other capability actually reachable.
2. **The mise parity pack.** `funes:spawn` (kill the iex incantation) → then
   `funes:dossier` / `funes:post` / `funes:roster`. Thin `mix` tasks. Gives you + me
   first-class funes access from the shell. (Likely a small `funes` CLI the tasks wrap.)
3. **The claude-code manos adapter.** Gives *me* the MCP tools directly — closes my gap the
   other way from mise, and makes Claude Code a first-class citizen like pi.
4. **Vocabulary slices** — todo (3), question (4), as planned.
5. **Measured verification** — `record_check` + the `verify`/`report-done` skills, on top of
   `cap`: evidence becomes measured, not self-reported; `check_passed`/`check_failed` events
   land; `fact.check_cmd` can be re-run to confirm facts still hold.
6. **open_thread / close_thread tools** — small, already designed.
7. **sandbox/cache allowlist** — small, anytime.
8. **arbiter** — the capstone, stays last.

The `cap` run-loop tooling (run once, structured failure, swept) is **done** and underlies
5.
