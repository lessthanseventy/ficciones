defmodule Aleph.KeymapTest do
  @moduledoc """
  The keyhandling contract, tested as a pure reducer with no TTY (design §8: the cockpit's one
  brain, extracted from its paint). `Aleph.Keymap.handle/2` maps `(key_event, state)` to
  `{new_state, effect}`; the Cockpit interprets the effect (`:repaint` / `:quit` /
  `{:forward, key}` / `{:create_thread, title}` / `{:enter_or_spawn, id}` / `:none`).

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): a live
  terminal in the center forwards every key by default; aleph's commands are reached through a
  `Ctrl+Space` leader (Ctrl+B belongs to tmux in the Tlön center and forwards like any key). With no live terminal, the same commands are bare. `center_live?` is derived by
  the cockpit; the tests set it directly. Every binding is asserted here so a regression like
  "Ctrl+C quit aleph again" or "arrows stopped moving focus" is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Keymap

  # The slice of cockpit state the keymap reads. Threads are anything with an `.id`.
  # `center_live?` and `composer_thread_id` are derived per keypress by the cockpit; here they're
  # set explicitly per test (`composer_thread_id` defaults to the focused thread).
  defp state(overrides \\ %{}) do
    base =
      Map.merge(
        %{
          active_key: :sessions,
          focused_id: 2,
          threads: [%{id: 1}, %{id: 2}, %{id: 3}],
          center_live?: false,
          leader_pending?: false,
          input: nil
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
      assert {%{active_key: :tlon}, :repaint} = Keymap.handle(key(:tab), state())
    end

    test "Shift-Tab moves to the previous space (wraps)" do
      assert {%{active_key: :tlon}, :repaint} =
               Keymap.handle(key(:tab, shift: true), state(%{active_key: :comms}))
    end

    test "] is next, [ is previous" do
      assert {%{active_key: :tlon}, :repaint} = Keymap.handle(char("]"), state())
      assert {%{active_key: :comms}, :repaint} = Keymap.handle(char("["), state())
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

    test "Enter on a focused thread asks to enter-or-spawn" do
      assert {_s, {:enter_or_spawn, 2}} = Keymap.handle(key(:enter), state(%{focused_id: 2}))
    end

    test "Enter with no focused thread is a no-op" do
      s = state(%{focused_id: nil, threads: []})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end

    test "Enter outside the Sessions space is a no-op — the spawned terminal couldn't be seen" do
      # In Comms the center renders the chorus and in Tlön the machine shell; a spawn from
      # either would start a live PTY the operator can't see or type into.
      for space <- [:comms, :tlon] do
        s = state(%{active_key: space})
        assert {^s, :none} = Keymap.handle(key(:enter), s)
      end
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
      assert {%{active_key: :tlon, leader_pending?: false}, :repaint} = via_leader(key(:tab), s)
    end

    test "^B Enter enters-or-spawns on the focused thread" do
      s = state(%{center_live?: true, focused_id: 2})
      assert {%{leader_pending?: false}, {:enter_or_spawn, 2}} = via_leader(key(:enter), s)
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
      # injection), so a focused_id carried over from Comms must not receive the post.
      s = state(%{active_key: :tlon, focused_id: 2, composer_thread_id: 99})
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
end
