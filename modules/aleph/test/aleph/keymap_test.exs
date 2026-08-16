defmodule Aleph.KeymapTest do
  @moduledoc """
  The keyhandling contract, tested as a pure reducer with no TTY (design §8: the cockpit's one
  brain, extracted from its paint). `Aleph.Keymap.handle/2` maps `(key_event, state)` to
  `{new_state, effect}`; the Cockpit interprets the effect (`:repaint` / `:quit` /
  `{:forward, key}` / `{:create_thread, title}` / `{:enter_or_spawn, id}` / `:none`).

  **Input model — tmux-style** (see `docs/plans/2026-08-16-aleph-tmux-style-input.md`): a live
  terminal in the center forwards every key by default; aleph's commands are reached through a
  `Ctrl+B` leader. With no live terminal, the same commands are bare. `center_live?` is derived by
  the cockpit; the tests set it directly. Every binding is asserted here so a regression like
  "Ctrl+C quit aleph again" or "arrows stopped moving focus" is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Keymap

  # The slice of cockpit state the keymap reads. Threads are anything with an `.id`.
  # `center_live?` is derived per keypress by the cockpit; here it's set explicitly per test.
  defp state(overrides \\ %{}) do
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
  end

  defp key(k, opts \\ []), do: Enum.into(opts, %{key: k})
  defp char(c, opts \\ []), do: Enum.into(opts, %{key: :char, char: c})
  defp leader, do: char("b", ctrl: true)

  # A helper: press the leader, then a key, against `state`. Asserts the leader arms the prefix.
  defp via_leader(next_key, s) do
    {armed, :repaint} = Keymap.handle(leader(), s)
    Keymap.handle(next_key, armed)
  end

  describe "the leader (Ctrl+B)" do
    test "Ctrl+B arms the next key as an aleph command (sets leader_pending?, repaints)" do
      assert {%{leader_pending?: true}, :repaint} = Keymap.handle(leader(), state())
    end

    test "Ctrl+C never quits — it is unbound in nav context (no live terminal)" do
      s = state(%{center_live?: false})
      assert {^s, :none} = Keymap.handle(char("c", ctrl: true), s)
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

  describe "commands via the Ctrl+B leader (reachable from inside a running terminal)" do
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

    test "^B Ctrl+B sends a LITERAL Ctrl+B through to the terminal (prefix-twice)" do
      s = state(%{center_live?: true})

      assert {%{leader_pending?: false}, {:forward, %{key: :char, char: "b", ctrl: true}}} =
               via_leader(leader(), s)
    end

    test "^B Ctrl+B with no live terminal just drops the prefix (nowhere to send it)" do
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
