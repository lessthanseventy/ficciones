# Aleph input model — tmux-style (the center owns the keys)

**Decision (banked on thread 10, 2026-08-16):** aleph's input model flips from vim-modal to
tmux-style. The center surface owns the keys by default; aleph's own commands are reached through a
`Ctrl+B` leader. This replaces the `center_focused?` boolean ("press Enter to drop into the
terminal, Ctrl+B to release") with a one-key `leader_pending?` flag ("press Ctrl+B to arm the next
key as an aleph command").

The earlier design (`2026-08-15-aleph-chat-comms-and-env-layout-design.md`) banked *"vim/lazygit
style nav throughout."* That was the right spirit — single discoverable keys, no hidden text field
eating keystrokes — but the literal modal-vim reading ("a default navigation mode you drop out of to
reach the terminal") fights a cockpit whose **primary job is hosting terminals.** Requiring `Enter`
to start typing into a terminal, and stealing `Ctrl+C` as a quit in the default mode, are both
footguns that disappear when the terminal is the default sink. So: **vim-inspired, not vim-imported.**
One default where the center owns the keys; one reserved leader to reach the multiplexer. No modal
ceremony.

## The model

**Default rule — the center surface owns the keys:**

- **Center is a live terminal** (Sessions/Tlön with a live session) → every key **forwards** to the
  PTY. The terminal is "normal mode"; you type into it immediately, no `Enter` required.
- **Center is not a terminal** (Comms' chorus surface, or a Sessions/Tlön placeholder before a
  session is spawned) → aleph's nav bindings are **bare** (`j`/`k` move, `Tab` switches spaces, `n`
  new thread, `Enter` enter-or-spawn, `q` quits).

**The leader `Ctrl+B`** routes the *next* key to aleph's command set regardless of surface — so you
can reach aleph from inside a running terminal without the app trapping you:

| `Ctrl+B` then… | action |
|---|---|
| `k` / `j` / `↑` / `↓` | move thread focus |
| `Tab` / `]` / `[` / `Shift-Tab` | switch spaces |
| `n` | new thread (title prompt → create + spawn) |
| `Enter` | enter-or-spawn on the focused thread |
| `q` | quit aleph |
| `Ctrl+B` | send a **literal** Ctrl+B through to the terminal (tmux's prefix-twice) |
| `Esc` / any unbound key | cancel the pending prefix, no action |

**`Ctrl+C` never quits aleph.** This is the footgun the old model had (`Ctrl+C` → `:quit` in nav
mode). Under the new model `Ctrl+C` forwards to the terminal when one is live (interrupts the child),
and is a no-op otherwise. Quit is `Ctrl+B q`, or bare `q` in a nav-default space.

## The `n`/`s` collapse — one `spawn_onto` path, two doors

The old model had two verbs: `n` (new thread) and `s` (spawn onto the focused thread). Bad UX —
creating a thread and spawning a session onto it are almost always one action, and the cockpit's
`create_thread` handler already called `spawn_onto` right after opening the thread. So:

- **`n`** stays as **new thread**: title prompt → on Enter, create the thread AND spawn a session
  onto it (one motion, unchanged effect `{:create_thread, title}`).
- **`s` is removed.** The "put a session on an existing focused thread" case becomes **`Enter` =
  enter-or-spawn**: if the focused thread already has a live session → no-op (it's already the
  center); if not → `spawn_onto(focused_id)`. New effect `{:enter_or_spawn, thread_id}`.

`Enter` only fires enter-or-spawn in the nav-default context (no live center). When a terminal is
live, `Enter` forwards to it (you may be in a REPL or `less`). Coherent: you press `Enter` to start
a session when none is live; once live, `Enter` belongs to the child.

## State

The keymap state slice loses `center_focused?` and gains:

- `leader_pending?` — the prefix is armed; the next key is an aleph command (cleared after one key).
- `center_live?` — **derived per keypress by the cockpit** from `center_terminal(state) != nil`
  (not stored), so the keymap knows whether to forward or run nav bindings as bare keys.

The cockpit stores only `leader_pending?`; `center_live?` is merged into the state handed to
`Keymap.handle/2` each dispatch and dropped on the way back.

## Deferred (out of this slice)

- **Text selection + OSC 52 copy.** The click-to-select that landed (`ecb416d`) selects aleph's own
  UI (panels, thread rows), not text inside the embedded terminal. Host-level Shift-drag selection
  doesn't work (aleph renders borders + labels + center cells as one flat termbox buffer). Needs a
  drag-select mode over `Terminal.cells/1` → OSC 52 to the host tty. Its own kickoff.
- **Host-side Kitty CSI-u parse (the shift+enter gap).** The `a1bca09` commit armed the
  *embedded* terminal's Kitty keyboard protocol (`\e[>1u`) so `input_key` encodes shifted keys. In
  practice **ctrl+v round-trips** — it's a control byte (`\x16`) that flows through termbox2 → raxol
  → aleph → the PTY as a raw byte, no modifier-decode needed, so pi's image-paste binding fires.
  What does **not** round-trip is **shift+enter**: the host sends a bare `\r` (no modifier info),
  and neither termbox2's C parser nor raxol's `input_parser.ex` decodes Kitty/modifyOtherKeys CSI-u
  sequences, so the shift bit is lost before aleph sees it. Fix needs raxol `input_parser.ex` to
  decode `\e[13;2u` (and the host tty put in the mode). Narrow scope: shifted *non-control* keys
  where the modifier is the only distinguishing info.