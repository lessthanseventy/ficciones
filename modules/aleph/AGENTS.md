# aleph — the cockpit

The TTY cockpit over `funes` (design: `docs/plans/2026-08-15-aleph-tui-design.md`). A full-screen
terminal app with three spaces — **Comms** (the chorus), **Sessions** (threads + their embedded
harness terminals), **Tlön** (the machine/dogfood workspace) — rendering funes' read models and
embedding real terminals via `ghostty`. Not a service: you launch it, sit at it, quit it.

## Run it

- `uqbar` (or `mise run aleph:run`) — launch in ghostty. Reaps a stale cockpit + self-heals an
  unwired `tlon` tmux session before starting.
- `mise run aleph:reset` — when Tlön is wired-wrong or aleph acts like stale code (a "crash" with no
  trace, an old cockpit still on :4041). It's almost always a stale process/session, not a bug: the
  BEAM doesn't hot-reload. DESTRUCTIVE — kills the cockpit + panes.
- `mise run aleph:test` (pure seams, headless) · `mise run aleph:check` (the gate).
- **A silent crash logs to `~/.cache/aleph/crash.log`.** Look there first — the alt-screen swallows
  the terminal output, so a crash otherwise leaves nothing.

## The law

- **Depends on funes, one-directionally.** aleph boots funes' OTP app and calls only what `Funes`
  exports (the `:boundary` compiler enforces it). funes NEVER depends on aleph.
- **Not supervised at boot — it grabs the TTY.** Runs only under `mix aleph.run` in a real terminal,
  never during `mix test`. Tests cover PURE seams only (`ghostty_key`, `tlon_launcher`,
  `crash_report`, …); anything touching the TTY or the GenServer is not unit-tested.
- **aleph runs its OWN funes on :4041 (`.dev` db)** — isolated from the always-up service on :4040.
  Dogfood crashes/junk threads stay in the sandbox; they never touch the real channel.

## Gotchas that bite

- **termbox2 is output-only here and aleph NEVER polls it**, so `tb_width()/tb_height()` are frozen
  at `tb_init` size — the size refresh lives in the poll path we don't call. aleph patches in a
  public `tb_resize/0` NIF (`mix.exs`) and calls it each tick. Don't assume termbox tracks resizes.
- **The termbox2 NIF is patched at compile time** (`mix.exs`: `ensure_termbox_nif` + friends):
  truecolor (64-bit attr), the install copy, and `tb_resize/0`. `deps/` is gitignored, so the
  patches self-heal on every compile — bump `raxol_terminal` and the anchors may break loudly.
- **Tlön's center is a real `tmux attach`** to a standing `tlon` session. pi is wired by
  `tmux new-session -e FUNES_*`: tmux runs window 0's command in the SERVER's environment, not the
  client's, so `-e` is how the identity reaches it. An unwired session (continuum-restored, or from
  before a fix) is self-healed by `aleph:run`; `aleph:reset` is the manual nuke.
- **The funes MCP adapter (`modules/manos/pi`) self-heals** on a lost session (404), stale token
  (401), or down node (5xx) by dropping + re-handshaking. A standing pi outlives an aleph restart,
  so a restart must not strand it.

## Verify

`mise run aleph:check` — format + warnings-as-errors + the headless suite. Green before commit.
