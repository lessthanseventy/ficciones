defmodule Aleph.Keymap do
  @moduledoc """
  The cockpit's keyhandling as a **pure reducer** (design §8): `(key_event, state) → {new_state,
  effect}`, with no TTY, no tmux, and no paint. Extracting the decision from the side effect is
  what makes every binding testable headlessly (`Aleph.KeymapTest`) — the `Aleph.Cockpit`
  GenServer stays a thin interpreter of the returned effect.

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): the center
  surface owns the keys by default. A **live terminal** in the center forwards every key to its PTY
  (the terminal is "normal mode"); aleph's own commands are reached through a `Ctrl+Space` **leader**
  that arms the *next* key as an aleph command. NOT Ctrl+B: that's tmux's prefix, and the Tlön
  center is literal tmux — Ctrl+B forwards like any other key so `C-b 2` reaches the real thing.
  When there's no live terminal (Orbis' chorus, or a placeholder before a session spawns), aleph's
  nav bindings are **bare** — the same command table, reached without the prefix. One command
  table, two doors. (Ctrl+Space arrives as Kitty CSI-u `\\e[32;5u` → `%{key: :space, ctrl: true}`
  under the disambiguate mode the cockpit arms on the host.)

  `state` is the slice of cockpit state keys touch: `active_key`, `focused_id`, `threads`,
  `center_live?` (derived per keypress by the cockpit — true when a live terminal is in the
  center), `composer_thread_id` (also derived per keypress — the thread the `c` verb composes
  onto: the focused thread, or the machine thread in Tlön), `leader_pending?` (the prefix is
  armed), `input` (the typing modal), `orbis_focus` (`:survey | :threads` — which cursor Orbis'
  `j/k` drives; `h`/`l` toggle it), `survey_cursor` (the Orbis survey's per-row cursor, clamped to
  the live world count), and `leaves` (the cached `Aleph.Orbis.rollup/0`, read-only here for its
  `worlds` list — the same cache the cockpit's `orbis_worlds/1` reads). A `key_event` is the
  `Raxol.Core.Events.Event` `data` map, e.g. `%{key: :up}` or `%{key: :char, char: "j"}`.

  Effects:

    * `:repaint` — state changed; reload funes reads and paint.
    * `:quit` — tear down and stop.
    * `{:forward, key}` — send this key to the focused session's embedded terminal.
    * `{:create_thread, title}` — open a new thread AND spawn a session onto it (the `n` verb).
    * `{:post_message, thread_id, body}` — post the composer's body to the focused thread as the
      operator (the `c` verb).
    * `{:cycle_coworker_model, profile}` — advance the active space's coworker driver model one
      step round `Aleph.Profiles.model_ring/0` and persist it (the `m` verb — the SETTINGS knob;
      only in a space with a coworker).
    * `{:cycle_pane_view, dir}` — cycle the World's right-pane view (Health↔Activity↔Leaves, one
      panel shown full-height at a time) by `dir` (+1/-1, the `[`/`]` verb, World nav only).
    * `{:switch_space, key}` — Enter on the Orbis survey (`orbis_focus == :survey`) zooms into the
      cursor row's world id — the same effect a survey-row click emits (D0.2).
    * `{:toggle_orbis_face}` — `a` (Orbis, bare) flips `orbis_face` survey↔author (D2.1); Esc in
      the author face emits the same effect to step back to the survey.
    * `:none` — nothing to do.

  `state.input` is `nil` normally, or `%{kind: :new_thread, buffer, cursor}` (the `n` verb) or
  `%{kind: :compose, thread_id, buffer, cursor}` (the `c` verb) while the operator is typing — a
  modal that captures EVERY key (so `q` types a "q", it does not quit) until Enter submits or Esc
  cancels. `cursor` is a grapheme offset into `buffer` (not always the end — Left/Right/Up/Down/
  Home/End move it, Ctrl+P/Ctrl+N alias Up/Down for hosts that don't deliver arrow keys, and
  Ctrl+A/Ctrl+E/Ctrl+U/Ctrl+K/Ctrl+W are readline's line-editing reflexes), and every
  edit (typing, Backspace, Shift+Enter's newline) acts AT the cursor, like a normal text box. In
  the composer, Shift+Enter inserts a newline (multiline bodies) instead of submitting.

  Orbis' AUTHOR face (D2, Chunk 1): `orbis_face :: :survey | :author` (default `:survey`) picks
  which center panel `Aleph.View` renders — `a` toggles it on, Esc steps back off.
  """
  alias Aleph.Panel
  alias Aleph.Profiles
  alias Aleph.Space
  alias Aleph.Tlon.Focus
  alias Aleph.Tlon.Settings

  # `Space.world?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

  @type effect ::
          :repaint
          | :quit
          | {:forward, map()}
          | {:create_thread, String.t()}
          | {:post_message, term(), String.t()}
          | {:cycle_coworker_model, String.t()}
          | {:settings_apply, {String.t(), :model | :permission}}
          | {:habit_action, :approve | :reject}
          | {:cycle_pane_view, integer()}
          | {:switch_space, atom() | non_neg_integer()}
          | {:toggle_orbis_face}
          | :tlon_enter
          | :tlon_preview
          | :none

  @doc "Map a key event against the current state to the next state and the effect to run."
  @spec handle(map(), map()) :: {map(), effect()}

  # Shift+Space (Kitty CSI-u \e[32;2u → %{key: :space, shift: true}) is just a space — normalize it
  # to a plain char up front so EVERY downstream path treats it identically: the composer inserts it,
  # a live terminal forwards a real space byte, nav ignores it like a bare space. Without this it
  # falls through to the drop-everything tables and vanishes. Ctrl+Space (the leader, has :ctrl, not
  # :shift) never matches here, so the prefix is untouched.
  def handle(%{key: :space, shift: true} = key, state) when not is_map_key(key, :ctrl),
    do: handle(%{key: :char, char: " "}, state)

  # --- input mode: a MODAL — every key belongs to the buffer until Enter/Esc, so a binding
  # letter (q, s, tab) types its character instead of firing. Must come first. ---
  def handle(%{key: :escape}, %{input: %{}} = state), do: {%{state | input: nil}, :repaint}

  # Shift+Enter in the composer inserts a newline (a multiline body) instead of submitting, AT
  # the cursor (not always the end — Up/Down can have moved it off the last line). Must precede
  # the plain-Enter clauses — %{key: :enter, shift: true} also matches %{key: :enter}.
  def handle(%{key: :enter, shift: true}, %{input: %{kind: :compose} = input} = state),
    do: {%{state | input: insert_at(input, "\n")}, :repaint}

  # Enter submits — but an empty buffer creates/posts nothing (cancel), never a blank thread/message.
  def handle(%{key: :enter}, %{input: %{buffer: ""}} = state), do: {%{state | input: nil}, :repaint}

  def handle(%{key: :enter}, %{input: %{kind: :new_thread, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:create_thread, buffer}}

  def handle(%{key: :enter}, %{input: %{kind: :compose, thread_id: id, buffer: buffer}} = state),
    do: {%{state | input: nil}, {:post_message, id, buffer}}

  # Backspace deletes the grapheme BEFORE the cursor (not always the buffer's last char — the
  # cursor can sit mid-buffer once Up/Down/Left/Right have moved it). A cursor at 0 is a no-op.
  def handle(%{key: :backspace}, %{input: %{}} = state),
    do: {%{state | input: delete_before_cursor(state.input)}, :repaint}

  # Left/Right move the cursor a grapheme; Home/End jump to the start/end of the CURRENT line (not
  # the whole buffer) — the usual text-box contract for a multiline composer.
  def handle(%{key: :left}, %{input: %{}} = state), do: {%{state | input: move_cursor(state.input, -1)}, :repaint}
  def handle(%{key: :right}, %{input: %{}} = state), do: {%{state | input: move_cursor(state.input, 1)}, :repaint}
  def handle(%{key: :home}, %{input: %{}} = state), do: {%{state | input: cursor_home(state.input)}, :repaint}
  def handle(%{key: :end}, %{input: %{}} = state), do: {%{state | input: cursor_end(state.input)}, :repaint}

  # Up/Down move a line, preserving column where possible — a no-op on a single-line buffer
  # (`new_thread`'s title). Ctrl+P/Ctrl+N are the readline aliases (previous/next line — the same
  # keys readline's history recall uses): some hosts (a nested tmux/SSH hop) don't deliver arrow
  # keys reliably, so this box always has a working up/down. MUST precede the generic char clause
  # below — %{key: :char, char: "p"} also matches a bare "p" keystroke.
  def handle(%{key: :up}, %{input: %{}} = state), do: {%{state | input: move_line(state.input, -1)}, :repaint}
  def handle(%{key: :down}, %{input: %{}} = state), do: {%{state | input: move_line(state.input, 1)}, :repaint}

  def handle(%{key: :char, char: "p", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: move_line(state.input, -1)}, :repaint}

  def handle(%{key: :char, char: "n", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: move_line(state.input, 1)}, :repaint}

  # Ctrl+A/Ctrl+E: the emacs/readline aliases for Home/End (current line, not the whole buffer) —
  # some hosts deliver these more reliably than the Home/End keycaps, and they're the muscle
  # memory a shell/readline already trained. MUST precede the generic char clause below, same
  # reason as Ctrl+P/Ctrl+N.
  def handle(%{key: :char, char: "a", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: cursor_home(state.input)}, :repaint}

  def handle(%{key: :char, char: "e", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: cursor_end(state.input)}, :repaint}

  # Ctrl+U: readline's unix-line-discard — kill from the start of the CURRENT line to the cursor.
  # Ctrl+K: readline's kill-line — kill from the cursor to the END of the current line (free to
  # bind now that Ctrl+P/Ctrl+N took over up/down). Ctrl+W: unix-word-rubout — kill the word
  # behind the cursor. All three are the "undo what I just typed" reflexes a shell trains.
  def handle(%{key: :char, char: "u", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_to_line_start(state.input)}, :repaint}

  def handle(%{key: :char, char: "k", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_to_line_end(state.input)}, :repaint}

  def handle(%{key: :char, char: "w", ctrl: true}, %{input: %{}} = state),
    do: {%{state | input: kill_word_backward(state.input)}, :repaint}

  # Printable keys insert AT the cursor, not append — so typing after moving the cursor lands
  # where you moved it, like a normal text box.
  def handle(%{key: :char, char: c}, %{input: %{}} = state) when is_binary(c),
    do: {%{state | input: insert_at(state.input, c)}, :repaint}

  # A space can arrive as %{key: :space} with no `char`: under [>1u disambiguation (which the cockpit
  # enables) Kitty CSI-u reports Shift+Space as [32;2u → %{key: :space, shift: true}. A plain space
  # is a printable %{key: :char, char: " "} caught above; this clause catches the modified form so it
  # inserts instead of falling to the drop-everything catch-all below.
  def handle(%{key: :space}, %{input: %{}} = state), do: {%{state | input: insert_at(state.input, " ")}, :repaint}

  # Any other key while typing (function keys, …) is ignored, not acted on.
  def handle(_key, %{input: %{}} = state), do: {state, :none}

  # --- Tlön settings modal (design §Settings): a MODAL like `input` — while open, every key belongs
  # to it (so `q` navigates, never quits) until `,`/Esc dismisses. j/k pick the coworker row, Tab or
  # h/l flip the model↔permission knob, Enter/Space applies (cycle the model ring / toggle yolo) and
  # leaves it open so you can keep adjusting. Must precede the Tlön focus dispatch below. ---
  def handle(%{key: :escape}, %{modal: %Settings{open?: true}} = state), do: {close_modal(state), :repaint}
  def handle(%{key: :char, char: ","}, %{modal: %Settings{open?: true}} = state), do: {close_modal(state), :repaint}

  def handle(%{key: :char, char: "j"}, %{modal: %Settings{open?: true}} = state),
    do: {modal_intent(state, :row_next), :repaint}

  def handle(%{key: :down}, %{modal: %Settings{open?: true}} = state), do: {modal_intent(state, :row_next), :repaint}

  def handle(%{key: :char, char: "k"}, %{modal: %Settings{open?: true}} = state),
    do: {modal_intent(state, :row_prev), :repaint}

  def handle(%{key: :up}, %{modal: %Settings{open?: true}} = state), do: {modal_intent(state, :row_prev), :repaint}
  def handle(%{key: :tab}, %{modal: %Settings{open?: true}} = state), do: {modal_intent(state, :field_next), :repaint}

  def handle(%{key: :char, char: "l"}, %{modal: %Settings{open?: true}} = state),
    do: {modal_intent(state, :field_next), :repaint}

  def handle(%{key: :char, char: "h"}, %{modal: %Settings{open?: true}} = state),
    do: {modal_intent(state, :field_next), :repaint}

  def handle(%{key: :enter}, %{modal: %Settings{open?: true} = m} = state),
    do: {state, {:settings_apply, Settings.target(m)}}

  def handle(%{key: :char, char: " "}, %{modal: %Settings{open?: true} = m} = state),
    do: {state, {:settings_apply, Settings.target(m)}}

  def handle(%{key: :space}, %{modal: %Settings{open?: true} = m} = state),
    do: {state, {:settings_apply, Settings.target(m)}}

  # Every other key is swallowed while the modal is up — nav mode never leaks a stray key to tmux.
  def handle(_key, %{modal: %Settings{open?: true}} = state), do: {state, :none}

  # --- Tlön: the lazygit focus model (design 2026-08-20). The center is a live tmux client, so
  # `Ctrl+Space` is a STICKY toggle in/out of it — NOT the arm-next-key leader other spaces use.
  # In the terminal every key forwards to tmux; out of it aleph owns the keys and drives the pure
  # `Aleph.Tlon.Focus` SM over `tlon_layout` (h/l pane · H/L column · s section · Esc→terminal).
  # `focus` (persistent) and `tlon_layout` (derived per keypress, like center_live?) are supplied by
  # the cockpit only for this space; the guard keeps every other space on the leader path below. ---
  def handle(key, %{active_key: k, focus: %Focus{}} = state) when Space.world?(k), do: handle_tlon(key, state)

  # --- leader pending: Ctrl+Space was pressed; the next key is an aleph command. ---
  # Ctrl+Space again → send a LITERAL Ctrl+Space through (the prefix-twice convention), so an
  # app that binds it (emacs set-mark!) still gets it. Only with a live terminal to receive it.
  def handle(%{key: :space, ctrl: true}, %{leader_pending?: true, center_live?: true} = state),
    do: {%{state | leader_pending?: false}, {:forward, %{key: :space, ctrl: true}}}

  def handle(%{key: :space, ctrl: true}, %{leader_pending?: true} = state), do: {%{state | leader_pending?: false}, :none}

  # Esc cancels a pending prefix without acting — the escape hatch from a half-armed leader.
  def handle(%{key: :escape}, %{leader_pending?: true} = state), do: {%{state | leader_pending?: false}, :repaint}

  # Any other key while the prefix is armed → run the command, then clear the prefix. The command
  # table (`command/2`) is the single source of aleph's bindings, shared with the bare-key path.
  def handle(key, %{leader_pending?: true} = state) do
    {next, effect} = command(key, state)
    {%{next | leader_pending?: false}, effect}
  end

  # --- the leader: Ctrl+Space arms the next key as an aleph command. ---
  def handle(%{key: :space, ctrl: true}, state), do: {%{state | leader_pending?: true}, :repaint}

  # --- default: the center surface owns the keys. ---
  # A live terminal in the center → every key forwards to its PTY. The terminal is "normal mode";
  # you type into it immediately. (Ctrl+C lands here too → forwards as an interrupt, never a quit.)
  def handle(key, %{center_live?: true} = state), do: {state, {:forward, key}}

  # No live terminal (Orbis, or a placeholder before a session spawns) → aleph's nav bindings are
  # bare — the same command table the leader reaches, just without the prefix.
  def handle(key, state), do: command(key, state)

  # --- aleph's command table — one source of bindings, reached two ways: bare in a nav-default
  # space, or via the Ctrl+Space leader from inside a running terminal. ---
  defp command(%{key: :char, char: "q"}, state), do: {state, :quit}

  defp command(%{key: :char, char: "n"}, state),
    do: {%{state | input: %{kind: :new_thread, buffer: "", cursor: 0}}, :repaint}

  # `a` (bare) toggles Orbis' author face on; Esc (below, no input open) toggles it back off.
  # Modifier-guarded like `c`/`m` — Ctrl/Shift/Alt+A never fires this.
  defp command(%{key: :char, char: "a"} = k, %{active_key: :orbis} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {state, {:toggle_orbis_face}}

  # Esc steps the author face back to the survey. Only reached with `input` nil (the input-mode
  # Esc clause up top intercepts first while typing) — a bare Esc on the survey face is a no-op,
  # nothing to close.
  defp command(%{key: :escape}, %{active_key: :orbis} = state) do
    if orbis_face(state) == :author, do: {state, {:toggle_orbis_face}}, else: {state, :none}
  end

  # `c` — the composer: post to the thread `composer_thread_id` (the focused thread in Orbis, the
  # machine thread in Tlön — resolved per keypress by the cockpit, like center_live?).
  # nil (empty board / no machine thread) → nothing to post on. Bare `c` only (modifiers nil):
  # Ctrl+C is unbound (never a quit) and must not open a composer. Bare in a nav space or via the
  # leader from a terminal.
  defp command(%{key: :char, char: "c"} = k, %{composer_thread_id: id} = state)
       when not is_nil(id) and not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt),
       do: {%{state | input: %{kind: :compose, thread_id: id, buffer: "", cursor: 0}}, :repaint}

  # `m` — cycle the active space's coworker driver model (the SETTINGS panel's one verb). Only
  # in a space WITH a coworker (elsewhere there's nothing to point the ring at), and bare `m`
  # only, same modifier discipline as `c`.
  defp command(%{key: :char, char: "m"} = k, %{active_key: key} = state)
       when not is_map_key(k, :ctrl) and not is_map_key(k, :shift) and not is_map_key(k, :alt) do
    case Space.fetch(key).coworker do
      nil -> {state, :none}
      profile -> {state, {:cycle_coworker_model, profile}}
    end
  end

  # Enter in the Orbis survey (focus == :survey) zooms into the CURSOR row's own world id — the
  # god-view → world zoom, resolved from `survey_cursor` against the live worlds list (D0.3 gives
  # every row an `id`). With focus on :threads, Enter has no verb here (falls to the plain no-op
  # below, same as "elsewhere") — the thread list has nothing for Enter to do (Slice 1). The
  # author face has no Enter verb yet either (opening the field editor is Chunk 2) — a no-op, not
  # an accidental zoom into the cursor world's space.
  defp command(%{key: :enter}, %{active_key: :orbis} = state) do
    cond do
      orbis_face(state) == :author ->
        {state, :none}

      orbis_focus(state) == :survey ->
        case Enum.at(survey_worlds(state), survey_cursor(state)) do
          %{id: id} -> {state, {:switch_space, id}}
          _ -> {state, :none}
        end

      true ->
        {state, :none}
    end
  end

  # Enter has no top-level verb elsewhere since the Slice 0 collapse: the Sessions space (its only
  # home — the one center that could show a spawned per-thread PTY) is gone, so Enter is a plain
  # no-op. In Tlön, Enter is routed by handle_tlon (commit-the-preview), never reaching this clause.
  defp command(%{key: :enter}, state), do: {state, :none}

  defp command(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp command(%{key: :tab}, state), do: switch(state, :next)

  # `h`/`l` toggle Orbis' focus between the survey (per-row cursor) and the thread list (the
  # existing `focused_id` nav) — Orbis-only; in a World, h/l belong to Focus pane-nav
  # (`handle_tlon`), never reaching this table.
  defp command(%{key: :char, char: "h"}, %{active_key: :orbis} = state), do: {toggle_orbis_focus(state), :repaint}

  defp command(%{key: :char, char: "l"}, %{active_key: :orbis} = state), do: {toggle_orbis_focus(state), :repaint}

  # j/k/↑/↓ route by `orbis_focus`: :survey moves the survey's per-row cursor (clamped, no wrap);
  # :threads keeps the pre-existing thread-focus move. Orbis-only (World j/k is `handle_tlon`'s).
  defp command(%{key: :up}, %{active_key: :orbis} = state), do: move_orbis(state, -1)
  defp command(%{key: :char, char: "k"}, %{active_key: :orbis} = state), do: move_orbis(state, -1)
  defp command(%{key: :down}, %{active_key: :orbis} = state), do: move_orbis(state, 1)
  defp command(%{key: :char, char: "j"}, %{active_key: :orbis} = state), do: move_orbis(state, 1)

  defp command(%{key: :up}, state), do: move(state, -1)
  defp command(%{key: :char, char: "k"}, state), do: move(state, -1)
  defp command(%{key: :down}, state), do: move(state, 1)
  defp command(%{key: :char, char: "j"}, state), do: move(state, 1)

  # Anything else (Ctrl+C, F-keys, page-up…) is unbound — a no-op, never a quit.
  defp command(_key, state), do: {state, :none}

  # --- Tlön focus routing. Ctrl+Space toggles the terminal; in the terminal every key forwards;
  # out of it the nav keys drive the focus SM and the bare commands (quit, space-switch, composer,
  # driver ring) stay reachable. Anything else no-ops — nav mode never leaks a key to tmux. ---
  defp handle_tlon(%{key: :space, ctrl: true}, state), do: {focus_intent(state, :toggle_terminal), :repaint}

  defp handle_tlon(key, %{focus: %Focus{in_terminal?: true}} = state), do: {state, {:forward, key}}

  # Esc steps back one level: close an open detail first, else drop out of nav into the terminal.
  defp handle_tlon(%{key: :escape}, %{focus: %Focus{detail?: true}} = state),
    do: {focus_intent(state, :close_detail), :repaint}

  defp handle_tlon(%{key: :escape}, state), do: {put_in(state.focus.in_terminal?, true), :repaint}
  # `,` opens the settings modal — the design's `Ctrl+Space ,` reaches here only in nav mode (an
  # in-terminal comma forwarded above, a literal `,` to the shell). The modal then owns the keys.
  defp handle_tlon(%{key: :char, char: ","}, state), do: {open_settings(state), :repaint}
  defp handle_tlon(%{key: :char, char: "l"}, state), do: {focus_intent(state, :pane_next), :repaint}
  defp handle_tlon(%{key: :char, char: "h"}, state), do: {focus_intent(state, :pane_prev), :repaint}
  defp handle_tlon(%{key: :char, char: "L"}, state), do: {focus_intent(state, :col_right), :repaint}
  defp handle_tlon(%{key: :char, char: "H"}, state), do: {focus_intent(state, :col_left), :repaint}
  # j/k move the item cursor within the focused pane; Enter opens its selection's detail in MAIN.
  # (Leaves' Enter is a space-jump, not a detail — Phase 4 special-cases it ahead of this clause.)
  # Over a WINDOW-BEARING pane (Leaves — each leaf maps to a live World tmux window) the move emits
  # `:tlon_preview` so the cockpit re-points the center to the hovered window (a hover, not a commit
  # — focus stays in nav); anywhere else it's a plain `:repaint`.
  defp handle_tlon(%{key: :char, char: "j"}, state), do: nav_move(state, :item_next)
  defp handle_tlon(%{key: :char, char: "k"}, state), do: nav_move(state, :item_prev)
  defp handle_tlon(%{key: :down}, state), do: nav_move(state, :item_next)
  defp handle_tlon(%{key: :up}, state), do: nav_move(state, :item_prev)
  # Enter is contextual: the cockpit resolves the focused pane and either opens a MAIN detail
  # (Commits/Memory) or jumps to a thread (Leaves) — the keymap can't, it lacks the reads.
  defp handle_tlon(%{key: :enter}, state), do: {state, :tlon_enter}
  # a/r act on the selected pending habit (Memory's habits section) — the cockpit resolves which
  # --- input-buffer cursor math (graphemes, not bytes) — what makes the composer/new-thread box
  # habit from the focus + reads and no-ops if the focus isn't on a habit. Approving writes it into
  # behave like a normal text field instead of an append-only log. `input.cursor` defaults to the
  # the recall floor; rejecting drops it.
  # buffer's end when absent (a state built before this field existed, or by an older test),
  # matching the old append-always behaviour exactly until something actually moves the cursor.

  defp handle_tlon(%{key: :char, char: "a"}, state), do: {state, {:habit_action, :approve}}
  defp handle_tlon(%{key: :char, char: "r"}, state), do: {state, {:habit_action, :reject}}
  # C3.4 reshuffle: Tab/Shift+Tab switch spaces (matching the command level) instead of cycling
  # sections — Shift+Tab must precede the bare :tab clause below, which also matches it.
  defp handle_tlon(%{key: :tab, shift: true}, state), do: switch(state, :prev)
  defp handle_tlon(%{key: :tab}, state), do: switch(state, :next)
  # `s` took over section-cycle (freed by Tab) — habits approve/reject needs focus.section == 1,
  # so the section must stay reachable.
  defp handle_tlon(%{key: :char, char: "s"}, state), do: {focus_intent(state, :section_next), :repaint}
  defp handle_tlon(%{key: :char, char: "q"}, state), do: {state, :quit}
  # `[`/`]` cycle the World's right-pane view (Health↔Activity↔Leaves, one full-height panel at a
  # time) — the cockpit resolves the active space's right-column length and wraps the index.
  defp handle_tlon(%{key: :char, char: "]"}, state), do: {state, {:cycle_pane_view, 1}}
  defp handle_tlon(%{key: :char, char: "["}, state), do: {state, {:cycle_pane_view, -1}}
  defp handle_tlon(%{key: :char, char: "c"} = k, state), do: command(k, state)
  defp handle_tlon(%{key: :char, char: "m"} = k, state), do: command(k, state)
  defp handle_tlon(_key, state), do: {state, :none}

  defp focus_intent(state, intent), do: %{state | focus: Focus.handle(state.focus, state.tlon_layout, intent)}

  # Move the item cursor, then decide the effect: over a window-bearing pane the cockpit should
  # preview (re-point the center) — `:tlon_preview`; elsewhere a plain `:repaint`. The cockpit
  # re-checks and no-ops the re-point if the hovered leaf has no live window.
  defp nav_move(state, intent) do
    next = focus_intent(state, intent)
    if window_bearing?(next), do: {next, :tlon_preview}, else: {next, :repaint}
  end

  # A pane whose selection maps to a live World tmux window — Leaves today (each leaf → its lead's
  # window). Only these drive the center preview.
  defp window_bearing?(state), do: Focus.focused_pane(state.focus, state.tlon_layout) == Panel.Leaves

  # The modal opens over the coworker profiles aleph actually materialises (Profiles.names) — the
  # only rows whose model/permission it can honestly write. A prior modal's row/field is preserved.
  defp open_settings(state) do
    base = state[:modal] || Settings.new(Profiles.names())
    Map.put(state, :modal, Settings.open(base))
  end

  defp close_modal(state), do: %{state | modal: Settings.close(state.modal)}
  defp modal_intent(state, intent), do: %{state | modal: Settings.handle(state.modal, intent)}

  defp switch(state, dir) do
    space =
      if dir == :next,
        do: Space.next(state.active_key),
        else: Space.prev(state.active_key)

    {%{state | active_key: space.key}, :repaint}
  end

  defp move(%{threads: []} = state, _dir), do: {state, :none}

  defp move(state, dir) do
    ids = Enum.map(state.threads, & &1.id)
    i = Enum.find_index(ids, &(&1 == state.focused_id)) || 0
    new_id = Enum.at(ids, min(max(i + dir, 0), length(ids) - 1))
    {%{state | focused_id: new_id}, :repaint}
  end

  # Dispatch Orbis' j/k/↑/↓ by which cursor is focused — the survey's per-row cursor, or the
  # pre-existing thread move (`move/2`, unchanged — keeps the composer's `c` target working).
  defp move_orbis(state, dir) do
    case orbis_focus(state) do
      :survey -> move_survey(state, dir)
      :threads -> move(state, dir)
    end
  end

  # Clamp `survey_cursor` into `0..length(worlds) - 1` — no wrap, same edge-clamp discipline as
  # `move/2`. Zero worlds clamps to 0 (harmless; Enter no-ops on an empty survey).
  # `Map.put/3`, not `%{state | ...}` — that raises KeyError when `:survey_cursor` is absent (an
  # older test's literal state map, built before this field existed), same tolerance as the
  # composer's `insert_at/2`.
  defp move_survey(state, dir) do
    max_idx = max(length(survey_worlds(state)) - 1, 0)
    cursor = (survey_cursor(state) + dir) |> max(0) |> min(max_idx)
    {Map.put(state, :survey_cursor, cursor), :repaint}
  end

  defp toggle_orbis_focus(state) do
    next = if orbis_focus(state) == :survey, do: :threads, else: :survey
    Map.put(state, :orbis_focus, next)
  end

  # Defaults tolerate a state map built before these fields existed (an older test's literal
  # state) — `:survey`/`0`, matching the cockpit's init-state defaults.
  defp orbis_focus(state), do: Map.get(state, :orbis_focus, :survey)
  defp survey_cursor(state), do: Map.get(state, :survey_cursor, 0)
  defp orbis_face(state), do: Map.get(state, :orbis_face, :survey)

  # The live worlds list Orbis' survey cursor/Enter resolve against — the same cached
  # `Aleph.Orbis.rollup/0` the cockpit's `orbis_worlds/1` reads (`state.leaves.worlds`). Kept local
  # (not a call into `Aleph.Cockpit`) so the keymap stays a pure reducer over its passed-in state.
  defp survey_worlds(state) do
    case Map.get(state, :leaves) do
      %{worlds: worlds} -> worlds
      _ -> []
    end
  end

  defp cursor_of(%{cursor: c}), do: c
  defp cursor_of(%{buffer: buffer}), do: String.length(buffer)

  # `Map.merge/2`, NOT the `%{input | ...}` update syntax — that raises KeyError when :cursor is
  # absent (an older test's literal input map, built before this field existed), and this must
  # tolerate that same as `cursor_of/1` does.
  defp insert_at(%{buffer: buffer} = input, text) do
    cursor = cursor_of(input)
    {before, aft} = split_at(buffer, cursor)
    Map.merge(input, %{buffer: before <> text <> aft, cursor: cursor + String.length(text)})
  end

  defp delete_before_cursor(%{buffer: buffer} = input) do
    cursor = cursor_of(input)

    if cursor <= 0 do
      Map.put(input, :cursor, 0)
    else
      {before, aft} = split_at(buffer, cursor)
      Map.merge(input, %{buffer: String.slice(before, 0..-2//1) <> aft, cursor: cursor - 1})
    end
  end

  defp move_cursor(%{buffer: buffer} = input, delta) do
    cursor = (cursor_of(input) + delta) |> max(0) |> min(String.length(buffer))
    Map.put(input, :cursor, cursor)
  end

  # Home/End act on the CURRENT line of a multiline buffer, not the whole thing — the line is
  # whatever's between the nearest "\n" before/after the cursor (buffer edges stand in when there
  # isn't one).
  defp cursor_home(%{buffer: buffer} = input), do: Map.put(input, :cursor, line_start_offset(buffer, cursor_of(input)))

  # The offset where the CURRENT line begins — shared by Home/Ctrl+A and Ctrl+U (kill-to-line-start
  # needs the same boundary Home jumps the cursor to).
  defp line_start_offset(buffer, cursor) do
    {before, _} = split_at(buffer, cursor)
    line = before |> String.split("\n") |> List.last()
    cursor - String.length(line)
  end

  # Ctrl+U: delete everything on the current line from its start up to the cursor. `before` is
  # buffer[0, cursor) already (from split_at), so slicing it to `start` (also measured from 0)
  # keeps everything before the line, drops everything the line had typed so far.
  defp kill_to_line_start(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    start = line_start_offset(buffer, cursor)
    {before, aft} = split_at(buffer, cursor)
    Map.merge(input, %{buffer: String.slice(before, 0, start) <> aft, cursor: start})
  end

  # Ctrl+W: delete the word behind the cursor — readline's unix-word-rubout. Walk `before`
  # backwards past trailing whitespace, then past the run of non-whitespace (the word), and keep
  # whatever's left.
  defp kill_word_backward(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    {before, aft} = split_at(buffer, cursor)

    {_ws, rest} =
      before |> String.graphemes() |> Enum.reverse() |> Enum.split_while(&(&1 in [" ", "\t", "\n"]))

    {_word, kept_reversed} = Enum.split_while(rest, &(&1 not in [" ", "\t", "\n"]))
    kept = kept_reversed |> Enum.reverse() |> Enum.join()
    Map.merge(input, %{buffer: kept <> aft, cursor: String.length(kept)})
  end

  defp cursor_end(%{buffer: buffer} = input), do: Map.put(input, :cursor, line_end_offset(buffer, cursor_of(input)))

  # The offset where the CURRENT line ends — shared by End/Ctrl+E and Ctrl+K (kill-to-line-end
  # needs the same boundary End jumps the cursor to).
  defp line_end_offset(buffer, cursor) do
    {_, aft} = split_at(buffer, cursor)

    line =
      case String.split(aft, "\n", parts: 2) do
        [first, _] -> first
        [first] -> first
      end

    cursor + String.length(line)
  end

  # Ctrl+K: delete everything on the current line from the cursor to its end (readline's
  # kill-line), leaving the cursor where it was.
  defp kill_to_line_end(%{buffer: buffer} = input) do
    cursor = cursor_of(input)
    end_offset = line_end_offset(buffer, cursor)
    {before, aft} = split_at(buffer, end_offset)
    kept_before = String.slice(before, 0, cursor)
    Map.put(input, :buffer, kept_before <> aft)
  end

  # Up/Down: move to the same COLUMN one line up/down (clamped to that line's length), the usual
  # text-editor contract. No line in that direction (top/bottom already) → no-op.
  defp move_line(%{buffer: buffer} = input, dir) do
    lines = String.split(buffer, "\n")
    {line_idx, col} = line_position(lines, cursor_of(input))
    target_idx = line_idx + dir

    if target_idx < 0 or target_idx >= length(lines) do
      input
    else
      target_line = Enum.at(lines, target_idx)
      new_col = min(col, String.length(target_line))
      Map.put(input, :cursor, line_start(lines, target_idx) + new_col)
    end
  end

  # Which line the cursor is on and its column within that line, walking lines left-to-right.
  defp line_position(lines, cursor) do
    Enum.reduce_while(lines, {0, cursor}, fn line, {idx, remaining} ->
      len = String.length(line)

      if remaining <= len,
        do: {:halt, {idx, remaining}},
        else: {:cont, {idx + 1, remaining - len - 1}}
    end)
  end

  # The cursor offset where `lines[target_idx]` begins — the sum of every earlier line's length
  # plus its trailing "\n".
  defp line_start(lines, target_idx) do
    lines |> Enum.take(target_idx) |> Enum.reduce(0, fn line, acc -> acc + String.length(line) + 1 end)
  end

  defp split_at(buffer, cursor) do
    graphemes = String.graphemes(buffer)
    {before, aft} = Enum.split(graphemes, cursor)
    {Enum.join(before), Enum.join(aft)}
  end
end
