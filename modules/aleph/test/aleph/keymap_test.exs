defmodule Aleph.KeymapTest do
  @moduledoc """
  The keyhandling contract, tested as a pure reducer with no TTY (design §8: the cockpit's one
  brain, extracted from its paint). `Aleph.Keymap.handle/2` maps `(key_event, state)` to
  `{new_state, effect}`; the Cockpit interprets the effect (`:repaint` / `:quit` /
  `{:forward, key}` / `{:create_thread, title}` / `:none`).

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): a live
  terminal in the center forwards every key by default; aleph's commands are reached through a
  `Ctrl+Space` leader (Ctrl+B belongs to tmux in the Tlön center and forwards like any key). With no live terminal, the same commands are bare. `center_live?` is derived by
  the cockpit; the tests set it directly. Every binding is asserted here so a regression like
  "Ctrl+C quit aleph again" or "arrows stopped moving focus" is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Keymap
  alias Aleph.Panel.Leaves
  alias Aleph.Tlon.Focus
  alias Aleph.Tlon.Settings

  # The slice of cockpit state the keymap reads. Threads are anything with an `.id`.
  # `center_live?` and `composer_thread_id` are derived per keypress by the cockpit; here they're
  # set explicitly per test (`composer_thread_id` defaults to the focused thread). `orbis_focus`
  # defaults to `:threads` here (NOT the cockpit's `:survey` init default) so the many pre-existing
  # thread-nav tests below keep exercising thread focus without every one of them overriding it;
  # the "Orbis survey cursor" describe block below sets `:survey` explicitly.
  defp state(overrides \\ %{}) do
    base =
      Map.merge(
        %{
          active_key: :orbis,
          focused_id: 2,
          threads: [%{id: 1}, %{id: 2}, %{id: 3}],
          center_live?: false,
          leader_pending?: false,
          input: nil,
          orbis_focus: :threads,
          survey_cursor: 0,
          leaves: nil
        },
        overrides
      )

    Map.put_new(base, :composer_thread_id, base.focused_id)
  end

  defp key(k, opts \\ []), do: Enum.into(opts, %{key: k})
  defp char(c, opts \\ []), do: Enum.into(opts, %{key: :char, char: c})
  defp leader, do: key(:space, ctrl: true)

  # A helper: press the leader, then a key, against `state`. Asserts the leader arms the prefix.
  defp via_leader(next_key, s) do
    {armed, :repaint} = Keymap.handle(leader(), s)
    Keymap.handle(next_key, armed)
  end

  describe "Shift+Space normalizes to a plain space" do
    test "in the composer it inserts a space, not a dropped key" do
      s = state(%{input: %{kind: :compose, thread_id: 1, buffer: "a", cursor: 1}})
      {next, :repaint} = Keymap.handle(key(:space, shift: true), s)
      assert next.input.buffer == "a "
    end

    test "with a live terminal it forwards a real space char (not the modified key)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: " "}}} = Keymap.handle(key(:space, shift: true), s)
    end

    test "Ctrl+Space is untouched — it still arms the leader" do
      assert {%{leader_pending?: true}, :repaint} = Keymap.handle(key(:space, ctrl: true), state(%{center_live?: true}))
    end
  end

  describe "the leader (Ctrl+Space)" do
    test "Ctrl+Space arms the next key as an aleph command (sets leader_pending?, repaints)" do
      assert {%{leader_pending?: true}, :repaint} = Keymap.handle(leader(), state())
    end

    test "Ctrl+C never quits — it is unbound in nav context (no live terminal)" do
      s = state(%{center_live?: false})
      assert {^s, :none} = Keymap.handle(char("c", ctrl: true), s)
    end

    test "Ctrl+B forwards to the terminal when one is live — it is tmux's prefix, not aleph's" do
      s = state(%{center_live?: true})
      k = char("b", ctrl: true)
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "Ctrl+C forwards to the terminal when one is live — never a quit" do
      s = state(%{center_live?: true})
      k = char("c", ctrl: true)
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end
  end

  describe "bare keys in a nav-default space (no live terminal)" do
    test "q quits" do
      assert {_state, :quit} = Keymap.handle(char("q"), state())
    end

    test "Tab moves to the next space and repaints" do
      assert {%{active_key: 0}, :repaint} = Keymap.handle(key(:tab), state())
    end

    test "Shift-Tab moves to the previous space (wraps)" do
      assert {%{active_key: 0}, :repaint} =
               Keymap.handle(key(:tab, shift: true), state(%{active_key: :orbis}))
    end

    test "[ and ] are unbound outside a World — nothing to cycle in Orbis (C3.4 reshuffle)" do
      s = state()
      assert {^s, :none} = Keymap.handle(char("]"), s)
      s2 = state(%{active_key: 0})
      assert {^s2, :none} = Keymap.handle(char("["), s2)
    end

    test "Down and j both move focus forward" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(key(:down), state(%{focused_id: 2}))
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(char("j"), state(%{focused_id: 2}))
    end

    test "Up and k both move focus backward" do
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(key(:up), state(%{focused_id: 2}))
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(char("k"), state(%{focused_id: 2}))
    end

    test "focus clamps at the top edge — no wrap" do
      assert {%{focused_id: 1}, :repaint} = Keymap.handle(key(:up), state(%{focused_id: 1}))
    end

    test "focus clamps at the bottom edge — no wrap" do
      assert {%{focused_id: 3}, :repaint} = Keymap.handle(key(:down), state(%{focused_id: 3}))
    end

    test "movement on an empty thread list is a no-op" do
      s = state(%{threads: [], focused_id: nil})
      assert {^s, :none} = Keymap.handle(key(:down), s)
    end

    test "Enter with orbis_focus == :threads is a no-op — nothing to zoom from the thread list" do
      s = state(%{active_key: :orbis, orbis_focus: :threads})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end
  end

  describe "the Orbis survey cursor (D0.1/D0.2/D0.3: orbis_focus == :survey, the cockpit default)" do
    @two_worlds [
      %{id: 11, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []},
      %{id: 22, name: "Freedonia", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
    ]

    defp survey_state(overrides \\ %{}),
      do: state(Map.merge(%{orbis_focus: :survey, leaves: %{worlds: @two_worlds}}, overrides))

    test "j/k (and ↑/↓) move survey_cursor, clamped 0..length(worlds)-1 — no wrap" do
      s = survey_state(%{survey_cursor: 0})
      assert {%{survey_cursor: 1}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{survey_cursor: 1}, :repaint} = Keymap.handle(key(:down), s)

      # stops at the last world — 2 worlds, index 1 is the ceiling.
      s1 = survey_state(%{survey_cursor: 1})
      assert {%{survey_cursor: 1}, :repaint} = Keymap.handle(char("j"), s1)
      assert {%{survey_cursor: 1}, :repaint} = Keymap.handle(key(:down), s1)

      # stops at 0 — no wrap below the floor either.
      assert {%{survey_cursor: 0}, :repaint} = Keymap.handle(char("k"), survey_state(%{survey_cursor: 0}))
      assert {%{survey_cursor: 0}, :repaint} = Keymap.handle(key(:up), survey_state(%{survey_cursor: 0}))
    end

    test "h/l toggle orbis_focus between :survey and :threads" do
      assert {%{orbis_focus: :threads}, :repaint} = Keymap.handle(char("h"), survey_state())
      assert {%{orbis_focus: :threads}, :repaint} = Keymap.handle(char("l"), survey_state())

      s = state(%{active_key: :orbis, orbis_focus: :threads})
      assert {%{orbis_focus: :survey}, :repaint} = Keymap.handle(char("h"), s)
      assert {%{orbis_focus: :survey}, :repaint} = Keymap.handle(char("l"), s)
    end

    test "with orbis_focus == :threads, j/k still move focused_id — compose unbroken" do
      s = survey_state(%{orbis_focus: :threads, focused_id: 2})
      assert {%{focused_id: 3, survey_cursor: 0}, :repaint} = Keymap.handle(char("j"), s)
      assert {%{focused_id: 1, survey_cursor: 0}, :repaint} = Keymap.handle(char("k"), s)
    end

    test "Enter zooms into the CURSOR row's own world id, not the first world's" do
      assert {_state, {:switch_space, 22}} = Keymap.handle(key(:enter), survey_state(%{survey_cursor: 1}))
      assert {_state, {:switch_space, 11}} = Keymap.handle(key(:enter), survey_state(%{survey_cursor: 0}))
    end

    test "Enter on an empty survey (funes down / no worlds) is a no-op, never a crash" do
      s = state(%{active_key: :orbis, orbis_focus: :survey, leaves: nil})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end
  end

  describe "the live terminal owns the keys by default" do
    test "a printable key forwards, not acted on locally" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "q"}}} = Keymap.handle(char("q"), s)
    end

    test "arrows forward while a terminal is live (the app scrolls/moves), not a thread move" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :up}}} = Keymap.handle(key(:up), s)
    end

    test "Tab forwards while a terminal is live (shell completion), not a space switch" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :tab}}} = Keymap.handle(key(:tab), s)
    end

    test "Enter forwards while a terminal is live, not an enter-or-spawn" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :enter}}} = Keymap.handle(key(:enter), s)
    end

    test "bare q forwards to the terminal (you might be typing q), not a quit" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "q"}}} = Keymap.handle(char("q"), s)
    end
  end

  describe "commands via the Ctrl+Space leader (reachable from inside a running terminal)" do
    test "^B q quits even when a terminal is live" do
      s = state(%{center_live?: true})
      assert {%{leader_pending?: false}, :quit} = via_leader(char("q"), s)
    end

    test "^B j moves thread focus without forwarding the j to the terminal" do
      s = state(%{center_live?: true, focused_id: 2})
      assert {%{focused_id: 3, leader_pending?: false}, :repaint} = via_leader(char("j"), s)
    end

    test "^B k moves thread focus backward" do
      s = state(%{center_live?: true, focused_id: 2})
      assert {%{focused_id: 1, leader_pending?: false}, :repaint} = via_leader(char("k"), s)
    end

    test "^B Tab switches spaces" do
      s = state(%{center_live?: true})
      assert {%{active_key: 0, leader_pending?: false}, :repaint} = via_leader(key(:tab), s)
    end

    test "^B Enter is a no-op since the Slice 0 collapse (no enter-or-spawn verb)" do
      # The leader lives in the Tlön terminal; there Enter has no top-level verb (the Orbis
      # survey's Enter-zooms clause is keyed to :orbis and never matches here).
      s = state(%{center_live?: true, focused_id: 2, active_key: 0})
      assert {%{leader_pending?: false}, :none} = via_leader(key(:enter), s)
    end

    test "^B n opens the title input modal" do
      s = state(%{center_live?: true})

      assert {%{input: %{kind: :new_thread, buffer: ""}, leader_pending?: false}, :repaint} =
               via_leader(char("n"), s)
    end

    test "leader twice sends a LITERAL Ctrl+Space through to the terminal (prefix-twice)" do
      s = state(%{center_live?: true})

      assert {%{leader_pending?: false}, {:forward, %{key: :space, ctrl: true}}} =
               via_leader(leader(), s)
    end

    test "leader twice with no live terminal just drops the prefix (nowhere to send it)" do
      s = state(%{center_live?: false})
      assert {%{leader_pending?: false}, :none} = via_leader(leader(), s)
    end

    test "^B Esc cancels the pending prefix without acting" do
      s = state(%{center_live?: true})
      {armed, :repaint} = Keymap.handle(leader(), s)
      assert {%{leader_pending?: false}, :repaint} = Keymap.handle(key(:escape), armed)
    end

    test "^B then an unbound key clears the prefix and no-ops" do
      s = state(%{center_live?: true})
      assert {%{leader_pending?: false}, :none} = via_leader(key(:f5), s)
    end
  end

  describe "creating a thread — the `n` verb + title input mode" do
    test "n (bare, nav context) opens title input (empty buffer) and repaints" do
      assert {%{input: %{kind: :new_thread, buffer: ""}}, :repaint} = Keymap.handle(char("n"), state())
    end

    test "n forwards to the terminal when one is live (use ^B n to open a new thread)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "n"}}} = Keymap.handle(char("n"), s)
    end

    test "printable keys accumulate into the buffer, not acted on locally" do
      s = state(%{input: %{kind: :new_thread, buffer: "fab"}})
      assert {%{input: %{buffer: "fabl"}}, :repaint} = Keymap.handle(char("l"), s)
      s2 = state(%{input: %{kind: :new_thread, buffer: "fabl"}})
      assert {%{input: %{buffer: "fable"}}, :repaint} = Keymap.handle(char("e"), s2)
    end

    test "keys that are bindings in normal mode are captured as text while typing (q does not quit)" do
      s = state(%{input: %{kind: :new_thread, buffer: "re"}})
      assert {%{input: %{buffer: "req"}}, :repaint} = Keymap.handle(char("q"), s)
    end

    test "backspace deletes the last character" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable"}})
      assert {%{input: %{buffer: "fabl"}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Enter on a non-empty buffer submits {:create_thread, title} and leaves input mode" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable review"}})
      assert {%{input: nil}, {:create_thread, "fable review"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer cancels (never creates a blank thread)" do
      s = state(%{input: %{kind: :new_thread, buffer: ""}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels input mode, creating nothing" do
      s = state(%{input: %{kind: :new_thread, buffer: "half typed"}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end
  end

  describe "composing a message — the `c` verb + composer mode" do
    test "c (bare, nav context) opens a composer on the focused thread" do
      assert {%{input: %{kind: :compose, thread_id: 2, buffer: ""}}, :repaint} =
               Keymap.handle(char("c"), state())
    end

    test "c with no focused thread is a no-op" do
      s = state(%{focused_id: nil, threads: []})
      assert {^s, :none} = Keymap.handle(char("c"), s)
    end

    test "in Tlön, c composes onto the MACHINE thread, not a stale project focused_id" do
      # The cockpit derives composer_thread_id from the machine thread in Tlön (a per-keypress
      # injection), so a focused_id carried over from Orbis must not receive the post.
      s = state(%{active_key: 0, focused_id: 2, composer_thread_id: 99})
      assert {%{input: %{kind: :compose, thread_id: 99, buffer: ""}}, :repaint} = Keymap.handle(char("c"), s)
    end

    test "c forwards to the terminal when one is live (use ^B c to open a composer)" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :char, char: "c"}}} = Keymap.handle(char("c"), s)
    end

    test "^B c opens a composer even when a terminal is live" do
      s = state(%{center_live?: true, focused_id: 2})

      assert {%{input: %{kind: :compose, thread_id: 2, buffer: ""}, leader_pending?: false}, :repaint} =
               via_leader(char("c"), s)
    end

    test "printable keys accumulate into the buffer, not acted on locally" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "sh"}})
      assert {%{input: %{buffer: "shi"}}, :repaint} = Keymap.handle(char("i"), s)
      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "shi"}})
      assert {%{input: %{buffer: "ship"}}, :repaint} = Keymap.handle(char("p"), s2)
    end

    test "binding letters are captured as text while composing (q does not quit)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "the "}})
      assert {%{input: %{buffer: "the q"}}, :repaint} = Keymap.handle(char("q"), s)
    end

    test "a :space key event inserts a space (Kitty CSI-u Shift+Space has no char)" do
      # Under [>1u disambiguation Shift+Space arrives as %{key: :space, shift: true} — no `char` —
      # so it must not fall to the drop-everything catch-all. Plain space (a :char " ") still works.
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "two"}})
      assert {%{input: %{buffer: "two "}}, :repaint} = Keymap.handle(key(:space, shift: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "two"}})
      assert {%{input: %{buffer: "two "}}, :repaint} = Keymap.handle(key(:space), s2)
    end

    test "backspace deletes the last character" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship"}})
      assert {%{input: %{buffer: "shi"}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Shift+Enter inserts a newline instead of submitting" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one"}})
      assert {%{input: %{buffer: "one\n"}}, :repaint} = Keymap.handle(key(:enter, shift: true), s)

      # a printable key after the newline lands on the second line
      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\n"}})
      assert {%{input: %{buffer: "one\nt"}}, :repaint} = Keymap.handle(char("t"), s2)
    end

    test "Shift+Enter in a title still submits (no newlines in thread titles)" do
      s = state(%{input: %{kind: :new_thread, buffer: "fable"}})
      assert {%{input: nil}, {:create_thread, "fable"}} = Keymap.handle(key(:enter, shift: true), s)
    end

    test "Enter on a non-empty buffer posts {:post_message, thread_id, body} and leaves input mode" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "shipped"}})
      assert {%{input: nil}, {:post_message, 2, "shipped"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on a multiline buffer posts the whole body (newlines intact)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo"}})
      assert {%{input: nil}, {:post_message, 2, "one\ntwo"}} = Keymap.handle(key(:enter), s)
    end

    test "Enter on an empty buffer cancels (never posts a blank message)" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: ""}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:enter), s)
    end

    test "Esc cancels the composer, posting nothing" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "half typed"}})
      assert {%{input: nil}, :repaint} = Keymap.handle(key(:escape), s)
    end

    test "Left/Right move the cursor, and typing inserts there instead of at the end" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "sip", cursor: 1}})
      assert {%{input: %{buffer: "ship", cursor: 2}}, :repaint} = Keymap.handle(char("h"), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 2}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:left), s2)

      s3 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 1}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:right), s3)
    end

    test "Left/Right clamp at the buffer's edges" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "hi", cursor: 0}})
      assert {%{input: %{cursor: 0}}, :repaint} = Keymap.handle(key(:left), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "hi", cursor: 2}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:right), s2)
    end

    test "backspace deletes BEFORE the cursor, not always the buffer's last character" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 2}})
      assert {%{input: %{buffer: "sip", cursor: 1}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "backspace at the start of the buffer is a no-op" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "ship", cursor: 0}})
      assert {%{input: %{buffer: "ship", cursor: 0}}, :repaint} = Keymap.handle(key(:backspace), s)
    end

    test "Home/End jump to the start/end of the CURRENT line, not the whole buffer" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 4}}, :repaint} = Keymap.handle(key(:home), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 4}})
      assert {%{input: %{cursor: 7}}, :repaint} = Keymap.handle(key(:end), s2)
    end

    test "Up/Down move a line, preserving column where possible" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(key(:up), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(key(:down), s2)
    end

    test "Up/Down clamp the column to a shorter target line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "a\nlong line", cursor: 8}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:up), s)
    end

    test "Up/Down are a no-op at the buffer's top/bottom line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 1}}, :repaint} = Keymap.handle(key(:up), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(key(:down), s2)
    end

    test "Ctrl+P/Ctrl+N alias Up/Down — hosts that swallow arrow keys still get vertical movement" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{cursor: 2}}, :repaint} = Keymap.handle(char("p", ctrl: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 1}})
      assert {%{input: %{cursor: 5}}, :repaint} = Keymap.handle(char("n", ctrl: true), s2)
    end

    test "typing after moving the cursor with Ctrl+P lands where the cursor moved, not at the end" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      {moved, :repaint} = Keymap.handle(char("p", ctrl: true), s)
      assert {%{input: %{buffer: "onXe\ntwo", cursor: 3}}, :repaint} = Keymap.handle(char("X"), moved)
    end

    test "Ctrl+A/Ctrl+E alias Home/End on the current line" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{cursor: 4}}, :repaint} = Keymap.handle(char("a", ctrl: true), s)

      s2 = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 4}})
      assert {%{input: %{cursor: 7}}, :repaint} = Keymap.handle(char("e", ctrl: true), s2)
    end

    test "Ctrl+U kills from the start of the current line to the cursor, leaving other lines intact" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 6}})
      assert {%{input: %{buffer: "one\no", cursor: 4}}, :repaint} = Keymap.handle(char("u", ctrl: true), s)
    end

    test "Ctrl+K kills from the cursor to the end of the current line, cursor unmoved" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "one\ntwo", cursor: 5}})
      assert {%{input: %{buffer: "one\nt", cursor: 5}}, :repaint} = Keymap.handle(char("k", ctrl: true), s)
    end

    test "Ctrl+W kills the word behind the cursor, past trailing whitespace" do
      s = state(%{input: %{kind: :compose, thread_id: 2, buffer: "post the update ", cursor: 16}})
      assert {%{input: %{buffer: "post the ", cursor: 9}}, :repaint} = Keymap.handle(char("w", ctrl: true), s)
    end
  end

  describe "the `m` verb — cycle the coworker driver model (the SETTINGS knob)" do
    test "in a coworker space (Tlön), bare `m` emits the cycle effect for that profile" do
      s = state(%{active_key: 0})
      assert {^s, {:cycle_coworker_model, "tertius"}} = Keymap.handle(char("m"), s)
    end

    test "reachable via the leader from inside the live terminal" do
      s = state(%{active_key: 0, center_live?: true})
      assert {%{leader_pending?: false}, {:cycle_coworker_model, "tertius"}} = via_leader(char("m"), s)
    end

    test "in a space without a coworker, `m` is a no-op" do
      s = state(%{active_key: :orbis})
      assert {^s, :none} = Keymap.handle(char("m"), s)
    end

    test "a modified m (Ctrl+M / Alt+M) never fires the settings verb" do
      s = state(%{active_key: 0})
      assert {^s, :none} = Keymap.handle(char("m", ctrl: true), s)
      assert {^s, :none} = Keymap.handle(char("m", alt: true), s)
    end

    test "with a live terminal and no leader, `m` types into the terminal like any key" do
      s = state(%{active_key: 0, center_live?: true})
      k = char("m")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end
  end

  describe "unknown keys" do
    test "an unbound key in a nav-default space is a no-op" do
      s = state()
      assert {^s, :none} = Keymap.handle(key(:f5), s)
    end

    test "an unbound key forwards when a terminal is live" do
      s = state(%{center_live?: true})
      assert {^s, {:forward, %{key: :f5}}} = Keymap.handle(key(:f5), s)
    end
  end

  # Tlön's lazygit focus model (design 2026-08-20): the center is a live tmux client, so Ctrl+Space
  # is a STICKY toggle in/out of it — NOT the arm-next-key leader other spaces use. In the terminal
  # every key forwards to tmux; out of it aleph owns the keys and drives the pure `Aleph.Tlon.Focus`
  # SM over `tlon_layout`. Both `focus` (persistent) and `tlon_layout` (derived per keypress, like
  # center_live?) are supplied by the cockpit only for this space.
  describe "Tlön focus nav" do
    # A Tlön state: `focus` + the two-column `tlon_layout` it navigates. center_live? is true (the
    # tmux client is always live) but the focus path — not center_live? — decides key routing here.
    defp tlon(focus \\ Focus.new(), overrides \\ %{}) do
      state(
        Map.merge(
          %{
            active_key: 0,
            # counts: :a has 3 items, :b 2, :c 4 — what j/k clamps against.
            center_live?: true,
            focus: focus,
            tlon_layout: %{left: [:a, :b], right: [:c], sections: %{}, counts: %{a: 3, b: 2, c: 4}}
          },
          overrides
        )
      )
    end

    defp nav_focus(overrides \\ %{}), do: struct(Focus.new(), Map.merge(%{in_terminal?: false}, overrides))

    test "Ctrl+Space toggles OUT of the terminal into nav mode — it does not arm the leader" do
      {next, :repaint} = Keymap.handle(leader(), tlon())
      assert next.focus.in_terminal? == false
      assert next.leader_pending? == false
    end

    test "Ctrl+Space again toggles back INTO the terminal" do
      {next, :repaint} = Keymap.handle(leader(), tlon(nav_focus()))
      assert next.focus.in_terminal? == true
    end

    test "in the terminal, every key forwards to tmux (unchanged tmux ownership)" do
      s = tlon()
      k = char("j")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "in nav mode, l/h move the focus down/up the current column" do
      {n1, :repaint} = Keymap.handle(char("l"), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.pane == 1
      {n2, :repaint} = Keymap.handle(char("h"), n1)
      assert n2.focus.pane == 0
    end

    test "in nav mode, H/L jump between the sidebar columns" do
      {n1, :repaint} = Keymap.handle(char("L"), tlon(nav_focus(%{column: :left})))
      assert n1.focus.column == :right
      {n2, :repaint} = Keymap.handle(char("H"), n1)
      assert n2.focus.column == :left
    end

    test "in nav mode, s cycles the focused pane's sections (C3.4: section-cycle moved off Tab)" do
      s = tlon(nav_focus(%{column: :left, pane: 0}), %{tlon_layout: %{left: [:a, :b], right: [:c], sections: %{a: 2}}})
      {n1, :repaint} = Keymap.handle(char("s"), s)
      assert n1.focus.section == 1
      {n2, :repaint} = Keymap.handle(char("s"), n1)
      assert n2.focus.section == 0
    end

    test "in nav mode, Tab and Shift+Tab switch spaces (consistent with the command level)" do
      # Two-space ring after the collapse: from Tlön, either direction lands on Orbis.
      s = tlon(nav_focus())
      assert {%{active_key: :orbis}, :repaint} = Keymap.handle(key(:tab), s)
      assert {%{active_key: :orbis}, :repaint} = Keymap.handle(key(:tab, shift: true), s)
    end

    test "in nav mode, j/k move the item cursor within the focused pane, clamped to its count" do
      {n1, :repaint} = Keymap.handle(char("j"), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.cursors[:a] == 1
      {n2, :repaint} = Keymap.handle(char("k"), n1)
      assert n2.focus.cursors[:a] == 0
    end

    test "in nav mode, Down/Up alias j/k for the item cursor" do
      {n1, :repaint} = Keymap.handle(key(:down), tlon(nav_focus(%{column: :left, pane: 0})))
      assert n1.focus.cursors[:a] == 1
      {n2, :repaint} = Keymap.handle(key(:up), n1)
      assert n2.focus.cursors[:a] == 0
    end

    # Preview-swap (Worlds Slice 0, tweak #1): j/k/arrows over a WINDOW-BEARING pane (Leaves — each
    # leaf maps to a live World tmux window) emit `:tlon_preview` so the cockpit re-points the center
    # to the hovered window WITHOUT taking focus. Over a non-window pane it stays a plain `:repaint`.
    defp leaves_layout, do: %{left: [:a, :b], right: [Leaves], sections: %{}, counts: %{Leaves => 3}}

    defp leaves_nav(overrides \\ %{}),
      do: tlon(nav_focus(Map.merge(%{column: :right, pane: 0}, overrides)), %{tlon_layout: leaves_layout()})

    test "in nav mode, j/k over the Leaves pane emit :tlon_preview (a hover re-points the center)" do
      assert {n1, :tlon_preview} = Keymap.handle(char("j"), leaves_nav())
      assert n1.focus.cursors[Leaves] == 1
      assert {_n2, :tlon_preview} = Keymap.handle(char("k"), n1)
    end

    test "in nav mode, Down/Up over the Leaves pane also emit :tlon_preview" do
      assert {_n1, :tlon_preview} = Keymap.handle(key(:down), leaves_nav())
      assert {_n2, :tlon_preview} = Keymap.handle(key(:up), leaves_nav())
    end

    test "in nav mode, j over a non-window pane stays a plain :repaint (no preview)" do
      assert {_n, :repaint} = Keymap.handle(char("j"), tlon(nav_focus(%{column: :left, pane: 0})))
    end

    test "in nav mode, Enter emits :tlon_enter (the cockpit resolves detail-vs-jump per pane)" do
      assert {_s, :tlon_enter} = Keymap.handle(key(:enter), tlon(nav_focus()))
    end

    test "in nav mode, a/r emit the habit action effect (the cockpit resolves which habit)" do
      assert {_s, {:habit_action, :approve}} = Keymap.handle(char("a"), tlon(nav_focus()))
      assert {_s, {:habit_action, :reject}} = Keymap.handle(char("r"), tlon(nav_focus()))
    end

    test "in nav mode with no detail open, Esc returns to the terminal" do
      {next, :repaint} = Keymap.handle(key(:escape), tlon(nav_focus()))
      assert next.focus.in_terminal? == true
    end

    test "in nav mode with a detail open, Esc closes the detail first (stays in nav)" do
      {next, :repaint} = Keymap.handle(key(:escape), tlon(nav_focus(%{detail?: true})))
      assert next.focus.detail? == false
      assert next.focus.in_terminal? == false
    end

    test "in nav mode, q still quits" do
      assert {_s, :quit} = Keymap.handle(char("q"), tlon(nav_focus()))
    end

    test "in nav mode, ] and [ cycle the right-pane view (C3.4 — space-switch moved to Tab)" do
      s = tlon(nav_focus())
      assert {^s, {:cycle_pane_view, 1}} = Keymap.handle(char("]"), s)
      assert {^s, {:cycle_pane_view, -1}} = Keymap.handle(char("["), s)
    end

    test "in nav mode, c opens the composer on the machine thread" do
      s = tlon(nav_focus(), %{composer_thread_id: 7})
      assert {%{input: %{kind: :compose, thread_id: 7}}, :repaint} = Keymap.handle(char("c"), s)
    end

    test "in nav mode, an unbound key is a no-op — nav mode never forwards to tmux" do
      s = tlon(nav_focus())
      assert {^s, :none} = Keymap.handle(char("z"), s)
    end

    test "a live composer modal still captures keys — focus never hijacks typing" do
      s = tlon(nav_focus(), %{input: %{kind: :compose, thread_id: 9, buffer: "", cursor: 0}})
      {next, :repaint} = Keymap.handle(char("l"), s)
      assert next.input.buffer == "l"
    end

    test "outside Tlön a present focus struct is ignored — Ctrl+Space arms the leader as before" do
      s = state(%{active_key: :orbis, center_live?: true, focus: Focus.new()})
      assert {%{leader_pending?: true}, :repaint} = Keymap.handle(leader(), s)
    end
  end

  # The Tlön settings modal (design §Settings): `,` from nav mode opens a key-invoked overlay over
  # the coworker profiles; while open it OWNS every key (a MODAL, like the composer) until `,`/Esc
  # dismisses. Enter/Space applies the selected knob (model ring cycle / yolo toggle) as an effect.
  describe "Tlön settings modal" do
    defp open_modal(overrides \\ %{}) do
      m = ["tertius"] |> Settings.new() |> Settings.open()
      tlon(nav_focus(), Map.merge(%{modal: m}, overrides))
    end

    test "in nav mode, ',' opens the modal over the materialised coworker profiles" do
      {next, :repaint} = Keymap.handle(char(","), tlon(nav_focus()))
      assert %Settings{open?: true, coworkers: ["tertius", "reviewer"]} = next.modal
    end

    test "in the terminal, ',' forwards to tmux — it does not open the modal (Ctrl+Space first)" do
      s = tlon()
      k = char(",")
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "while open, Tab flips the selected knob model <-> permission" do
      {n1, :repaint} = Keymap.handle(key(:tab), open_modal())
      assert Settings.target(n1.modal) == {"tertius", :permission}
      {n2, :repaint} = Keymap.handle(key(:tab), n1)
      assert Settings.target(n2.modal) == {"tertius", :model}
    end

    test "while open, Enter applies the selected knob (model by default) as an effect" do
      assert {_s, {:settings_apply, {"tertius", :model}}} = Keymap.handle(key(:enter), open_modal())
    end

    test "while open on the permission knob, Enter applies a permission change" do
      {on_perm, :repaint} = Keymap.handle(key(:tab), open_modal())
      assert {_s, {:settings_apply, {"tertius", :permission}}} = Keymap.handle(key(:enter), on_perm)
    end

    test "while open, Space also applies (the alternate apply key)" do
      assert {_s, {:settings_apply, {"tertius", :model}}} = Keymap.handle(key(:space), open_modal())
    end

    test "apply leaves the modal open so you can keep adjusting" do
      {next, {:settings_apply, _}} = Keymap.handle(key(:enter), open_modal())
      assert next.modal.open?
    end

    test "',' and Esc both dismiss the modal" do
      {n1, :repaint} = Keymap.handle(char(","), open_modal())
      refute n1.modal.open?
      {n2, :repaint} = Keymap.handle(key(:escape), open_modal())
      refute n2.modal.open?
    end

    test "while open, the modal OWNS every key — q navigates, it does not quit" do
      assert {_s, :none} = Keymap.handle(char("q"), open_modal())
    end
  end
end
