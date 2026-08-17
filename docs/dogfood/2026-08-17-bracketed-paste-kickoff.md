# Tlön dogfood build — bracketed-paste passthrough in aleph

You're building **aleph** from inside Tlön. Read `modules/aleph/AGENTS.md` first (Law, gotchas, run/test).

## The bug (confirmed)

Pasting into aleph's embedded terminal (the Tlön/Sessions center) decodes as **individual
keystrokes**: aleph enables no bracketed paste, so ghostty's paste bytes reach raxol's `InputParser`
one char at a time — every `\n` becomes `:enter` and submits, chars trickle in. Grep proves the gap:
nothing in `modules/aleph/` touches `2004` / `200~` / `201~`. The operator wants a paste (Ctrl+Shift+V)
to land as ONE block; Ctrl+V stays free for pi's image paste (that split is ghostty's own keybinding,
not your concern).

## The fix — three coupled parts, each with a precedent already in this repo

1. **Host mode.** In `Aleph.Cockpit`, add `@paste_enable "\e[?2004h"` / `@paste_disable "\e[?2004l"`
   next to `@kitty_enable`/`@kitty_disable`; `IO.write(@paste_enable)` in `init` right after the
   `IO.write(@kitty_enable)` line, and disable it in the teardown path where the kitty stack is popped
   (`restore_host_tty` / `terminate/2` — find where `@kitty_disable` is written and mirror it). Now
   ghostty wraps a paste in `\e[200~…\e[201~` on aleph's host tty.

2. **Parse the markers — a raxol dep-patch, mirroring the kitty CSI-u patch.** `\e[200~` and `\e[201~`
   are CSI-tilde sequences (n=200 / n=201, terminator `~`), so they route through
   `parse_csi_tilde_one/1` in raxol's `input_parser.ex` — the SAME function the kitty patch already
   extends. Copy the mechanism verbatim from `mix.exs`: see `ensure_raxol_kitty_parser/1`,
   `@kitty_parser` (the dep path), `@kitty_csi_u_clauses` (inserted into the `case`), and the
   idempotence marker (`String.contains?(src, "defp csi_u_event")`). Add clauses that surface
   **paste-start (200)** and **paste-end (201)** as events — decide the event shape by reading how
   `csi_u_event` builds `key_event(...)`; a `%Event{}` with a distinct type/key the cockpit can match
   is fine. `deps/` is gitignored, so anchor-check and **RAISE loudly on an anchor miss** (exactly like
   the kitty patch — a soft warning would let a raxol bump ship an unpatched parser green). Register
   your patch step in the `compile` alias next to `&ensure_raxol_kitty_parser/1`.

3. **Buffer + forward as a block.** aleph holds a paste buffer in cockpit state: on **paste-start**,
   start collecting; while pasting, content keys accumulate into the buffer (a newline stays `\n`, NOT
   forwarded as `:enter`); on **paste-end**, forward the whole buffer to the center terminal wrapped as
   `\e[200~<buffer>\e[201~` via `Aleph.Terminal.feed/2` (raw bytes — `feed` exists for exactly this).
   aleph → tmux → pi: tmux passes bracketed paste through, and pi honors it as one multi-line paste.

## Quality bar (aleph's Law)

- **TDD the pure seams:** the InputParser paste decode (a `\e[200~x\e[201~` byte stream → paste-start
  / char / paste-end events, testable like the kitty CSI-u tests in `input_parser`'s patch) and the
  paste-buffer state machine in the cockpit (start → chars+newlines accumulate → end → one `feed`).
  Pin the raxol patch didn't-drift by asserting a decoded paste event, like the kitty tests do.
- **The end-to-end is a LIVE eye-test only the human can run:** Ctrl+Shift+V a 10-line block into the
  Tlön pane → it lands as ONE input with newlines intact, not ten submits. Say so explicitly in your
  handoff — green unit tests are necessary but not sufficient across the aleph→tmux→pi layers.
- Render/input can't crash the cockpit; comments load-bearing only; update any doc a surface change
  makes stale (same commit); `mise run aleph:check` green before each commit; commit as who you are
  (`Co-Authored-By: <your model> …`, read from your brief — never a copied name).

## Context (don't conflict)

Recent aleph commits (all local, `dogfood-kitty-keys`): the Tlön center is now a real tmux with an
aleph-rendered **tab strip** (row 0 of the center; `Panel.Terminal.tab_rows`/`tab_at_x`), tmux's own
status bar off, **clickable tabs**, and **mouse drag-selection** forwarded to tmux
(`Aleph.Terminal.mouse/4`, `forward_terminal_mouse`). Your input path shares the cockpit's key/mouse
dispatch — the paste buffer is new cockpit state alongside `leader_pending?`. The tab strip means the
center's row 0 is chrome; paste content targets the terminal regardless.

## Done

Ctrl+Shift+V a multi-line block into the Tlön pane → one paste with newlines intact, not N submits.
