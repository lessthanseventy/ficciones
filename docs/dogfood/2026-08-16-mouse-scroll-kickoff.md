# Dogfood task #1 — mouse-wheel scroll in aleph's center terminal

**Paste the block below into the Tlön coworker (pi-machine)** — or press `n` in aleph to open a
dedicated "mouse-wheel scroll" thread and spawn a fresh pi there. You're already on branch
`dogfood/mouse-scroll`; restore point is tag `pre-dogfood-2026-08-16` + `funes.db.pre-dogfood.bak`.

---

You are the Tlön machine coworker working on the **ficciones** repo itself (Elixir/mise; drive
everything through `mise` tasks — never a second way). **Task: add mouse-wheel scrollback to
aleph's embedded center terminal.** Right now the wheel does nothing; you can't scroll back through
a session's output.

**Do not re-derive the API surface — it's already been researched. Verify, don't guess:**

1. **Raxol already translates mouse events.** `deps/raxol_terminal/lib/raxol/terminal/driver/event_translator.ex`
   emits `%Raxol.Core.Events.Event{type: :mouse, data: %{x, y, button}}` with `button` of
   `:wheel_up` / `:wheel_down`. They only arrive **if termbox is in mouse input mode.**
2. **Enable termbox mouse input.** The cockpit's `init` (`modules/aleph/lib/aleph/cockpit.ex`, ~line 71)
   sets the *output* mode but leaves *input* at the default (`TB_INPUT_ESC`). Call
   `:termbox2_nif.tb_set_input_mode/1` with `ESC | MOUSE`. Find the real constant values under
   `deps/raxol_terminal/lib/termbox2_nif/` (termbox2 is `TB_INPUT_ESC=1`, `TB_INPUT_MOUSE=4` →
   `5`, but **confirm from the source**).
3. **Ghostty can both forward and scroll.** `deps/ghostty/lib/ghostty/terminal.ex` exposes
   `input_mouse/2` (encode a `Ghostty.MouseEvent` → escape sequence → PTY, exactly like `input_key`),
   `mouse_modes/1` (whether the embedded app requested mouse tracking), and `scroll/2` (scroll the VT
   scrollback). See `deps/ghostty/lib/ghostty/mouse_event.ex` for the struct.

**Behavior to implement:**

- **Cockpit:** a NEW `handle_cast({:dispatch, %Event{type: :mouse, data: %{x, y, button}}}, state)`
  clause beside the existing `:key` / `:resize` ones (~line 117–123). Act on the **center** terminal —
  reuse `center_terminal(state)` (it already resolves Sessions-vs-Tlön). Only when the wheel is over
  the center region (gate on `x`; the View lays out left ¼ / center ½ / right ¼, and `center_dims/1`
  approximates it).
- **Two paths (the "feels native" part):** if the embedded app has mouse tracking on
  (`mouse_modes` — pi in `/tui` likely does), **forward** the wheel to the app so it scrolls its own
  view; otherwise **scroll the Ghostty scrollback** (shell history). Put this behind a new
  `Aleph.Terminal` seam (e.g. `wheel(term, direction, n)` that branches on `mouse_modes` and calls
  `input_mouse` or `scroll`) — keep the ghostty/mouse detail in `Aleph.Terminal`, not the cockpit.

**Guardrails:**

- Stay on `dogfood/mouse-scroll`. **Do not touch `main`.** Commit small, clear messages.
- Elixir house rule: **function-head dispatch over a two-element `case` or a function wrapping an `if`.**
- The gate is `mise run aleph:check` (compile + tests) — run it (via `mise run cap -- mise run
  aleph:check` to capture once) and it must be **green** before you claim done.
- **TDD the pure bits:** which terminal a wheel-at-`x` targets, and `:wheel_up` → scroll-delta sign,
  are unit-testable in the `test/aleph/keymap_test.exs` / `board_test.exs` style. The live scroll is
  an **eye-test only Andrew can run in ghostty** — so structure it as *tested pure decision* + *thin
  NIF edge*.
- You're a funes citizen: `raise_question` on an unknown, `record_check` after the gate passes,
  `raise_issue` if you find something broken beyond scope. Keep your todos current.

**Done =** `mise run aleph:check` green + a one-line note of exactly what to eye-test (open aleph →
Tlön or Sessions → wheel over the center → scrollback moves; and that keys still work with mouse
mode on).

---
