# Per-thread reply input — design

**Date:** 2026-09-01
**Status:** designed, ready to implement
**Context:** Andrew, after the two-step center landed — "I don't want to have to hit `c`
to compose a new message into a thread; that's lame UX. It just needs another multiline
input for the thread scope. Or maybe 'start a new thread' can go away when we're in one."

## Problem

The two-step center (bfacd8e) gives a thread LIST → an opened CONVERSATION. But the
per-thread reply was never actually built: `Panel.ThreadStack.conversation/2` prints a
dead hint `↳ reply to #7… (c)`, and to reply you hit `c`, which pops the separate
`Panel.Composer` band above the status bar. This is the tier-1 input the `Panel.NewThread`
moduledoc always described ("each thread gets a reply") — stubbed as a keybind instead of
a real input.

## Model

The center already has two steps; the persistent bottom band gets the **same two steps, in
lockstep**. One band, two faces, never both.

| Center step | Bottom band | Focus & keys |
|---|---|---|
| **LIST** (`opened_thread == nil`) | `NewThread` — "＋ start a new thread…" (idle placeholder; `n`/click to focus) | `j/k` move cursor · `Enter` opens · `n` focus new-thread |
| **CONVERSATION** (`opened_thread == id`) | **`Reply`** — "↳ reply to #7 ▎" (**focused by default**, caret live on open) | type → reply box · `Enter` send · `Shift+Enter` newline · `PgUp/PgDn` + wheel scroll · `Esc` back to list |

Key properties:

- **`c` is retired from the workspace chat flow.** Opening a thread *is* focusing the
  reply — no verb. (`c`/`Composer`/`composer_thread_id` stay live for Orbis project threads
  and terminal-view; untouched.)
- **The asymmetry is deliberate.** In the LIST the primary act is navigate/pick, so `j/k`
  own the arrows and new-thread is opt-in via `n`. In a CONVERSATION the primary act is
  reply, so the box owns typing and scrolling is opt-in via `PgUp`/wheel. Mirrors a chat
  app's sidebar-vs-open-thread.
- **The new-thread band is hidden while a thread is open** (Andrew's "maybe" — yes).
- **Draft lifetime (v1, YAGNI):** the reply buffer lives while the thread stays open; `Esc`
  back-to-list discards it. No per-thread draft map yet.
- **Empty `Enter` = no-op** — stays focused, never posts blank, never closes.
- **Scroll keys:** `PgUp`/`PgDn` + mouse wheel only. No half-page `Ctrl+U/D` — those are
  readline kills inside the box (`Ctrl+U` = kill-to-line-start), so they'd collide.

### Accepted consequence

Opening a thread sets `state.input`, and the keymap's input modal owns **every** key while
input is set. So while a conversation is open, `Alt+N`/`h`/`l`/leader/etc. do not fire —
`Esc` (→ list) is the gateway back to nav and chords. This matches how the `c` composer
already swallows keys today; it's just persistent now instead of transient. If global chords
during reply are wanted later, hoist Alt-modified/leader keys above the input modal — a
follow-up, out of scope for v1.

## Implementation seams

### 1. New input kind `:reply`
`%{kind: :reply, thread_id, buffer, cursor}`. Seeded automatically — no verb:
- `Console.Cockpit.apply_effect({:open_thread_view, id})` (cockpit.ex:1599) also sets
  `input: %{kind: :reply, thread_id: id, buffer: "", cursor: 0}`.
- `apply_effect(:close_thread_view)` (cockpit.ex:1609) also sets `input: nil`.

### 2. New `Panel.Reply`
Sibling of `Panel.NewThread`, shares `Console.Text.wrap`. Always renders the live buffer +
`▎` caret — no idle placeholder (it's born focused). Prefix `↳ reply to #<id> ▸ `.
`Console.View.data_for(Panel.Reply, r) → %{input: r[:input]}`. Height grows with the buffer.

### 3. View swap
Parallel to `chat_center`'s `{Terminal,:machine} → ThreadStack` swap: when `opened_thread`
is set, map the center surface's `NewThread → Reply`. Generalize `new_thread_overrides` to
grow whichever band is present. Delete the dead `reply_row` stub from
`Panel.ThreadStack.conversation/2`.

### 4. Keymap — new clauses inside the input modal (before the generic clauses)

| Key | `:reply` behavior |
|---|---|
| `Enter` (empty buffer) | no-op, `:repaint` — stays focused, never closes (precede keymap.ex:181) |
| `Enter` (non-empty) | `{:post_message, thread_id, buffer}` + reset buffer to `""`, keep `kind: :reply` (like the compose clause at 219 but does NOT `input: nil`) |
| `Shift+Enter` | add `:reply` to the `kind in [...]` list at keymap.ex:177 |
| `Esc` | `{:close_thread_view}` + clear input — precede the generic Esc at keymap.ex:172 |
| `:page_up`/`:page_down` | `{:scroll_conversation, ∓N}` — precede the ignore catch-all at keymap.ex:303 |

Text editing (printable chars, backspace, Left/Right/Home/End, Up/Down, Ctrl+A/E/U/K/W,
Ctrl+P/N) is **inherited free** — every editing clause matches `%{input: %{}}` generically.

### 5. Retire from the chat flow
- `handle_tlon` `c`-verb clause (keymap.ex:712) — no longer opens a composer in chat view.
- LIST/CONVERSATION `j/k`-scroll clauses (keymap.ex:702–705) — `j/k` now type into the box.
- Keep `Composer`, `composer_thread_id`, and the `c` command clause for Orbis + terminal
  view (they route through `composer_thread_id`, which still has its non-chat clauses).

## Testing

Pure-reducer coverage (no TTY), the house style for keymap/view:

- **Keymap:** open a thread → `input.kind == :reply`; typing inserts; `Enter` on non-empty
  emits `{:post_message, id, body}` and leaves `kind: :reply` with `buffer: ""`; `Enter` on
  empty is a no-op keeping input; `Shift+Enter` inserts `\n`; `Esc` emits
  `{:close_thread_view}` and clears input; `PgUp`/`PgDn` emit `{:scroll_conversation, _}`.
- **View:** with `opened_thread` set the center surface contains `Panel.Reply` and NOT
  `Panel.NewThread`; with it nil the reverse. Height grows with buffer line count.
- **Panel.Reply:** renders the buffer with the caret at the cursor; multiline wraps under
  the prefix.
- **Verify live** (`/verify`): open a thread, type, Enter posts and clears, PgUp scrolls
  backlog, Esc returns to the list showing the new-thread band again.
