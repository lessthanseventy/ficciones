# manos · claude-code adapter

The hands for **Claude Code** — what makes a `claude` session a funes citizen, the peer of
the [pi adapter](../pi). Same **two-doors-one-identity** shape as pi, adapted to Claude
Code's own mechanisms.

## The identity

A session's identity is `(thread, agent="claude-code")`, carried in the environment
(`FUNES_THREAD`, `FUNES_AUTHOR`) exactly like a pi pane. You get it by launching through
the loop, never by hand:

```
mise run funes:claude              # opens a fresh thread, launches claude on it
mise run funes:claude -- 42        # JOINS thread 42 (resume a task across a /clear)
```

The launcher `eval`s the export block from `funes:spawn` and `exec`s `claude`.

## The two doors

Both reach the **live** funes service node (loopback MCP on :4040); the service must be up
(`systemd --user` unit).

- **Door 1 — the MCP tools.** Claude Code's `mcpServers.funes` entry is `type: http`
  pointing at the channel, with a **`headersHelper`** (`scripts/funes-cli.sh token`) instead
  of a static bearer. Claude Code runs the helper on every connect and reconnect; it mints a
  **fresh** funes token for `(FUNES_THREAD, FUNES_AUTHOR)` each time, so auth survives a funes
  restart and a 401 auto-refreshes. No token is ever written to disk. This is the key
  divergence from pi (whose extension reads a static `FUNES_TOKEN` once) — Claude Code
  supports dynamic headers, so it uses them.
- **Door 2 — the brief.** [`brief-hook.sh`](brief-hook.sh) is a `SessionStart` hook. Claude
  Code adds its plain stdout to the session context, so on start / resume / clear it renders
  the thread's dossier (the same `Board.in_scope → Brief` as `get_dossier`) and Claude
  re-orients from funes. No identity, a down channel, or a missing thread → a silent no-op;
  it never blocks the session.

## Install

Declarative, via home-manager (`flake.nix`), the same merge-not-own pattern as the pi
adapter's `manosWiring`: the `mcpServers.funes` entry and the `SessionStart` hook are merged
into `~/.claude` settings idempotently. `home:switch` is the human's.

## Why not a static token / a SessionStart env-mint

A funes token is ephemeral (in-memory registry, dies on service restart) and bound to a
`(thread, agent)`. Claude Code expands `${VAR}` in `.mcp.json` only **once at startup** from
the launch environment, and a `SessionStart` hook fires **before** MCP servers connect and
can't set env for them — so neither can carry a refreshing token. `headersHelper` is the only
mechanism that re-mints per connection, which is why the adapter is built on it. (Requires
Claude Code ≥ 2.1.195.)
