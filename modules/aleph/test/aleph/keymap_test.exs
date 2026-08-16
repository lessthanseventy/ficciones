defmodule Aleph.KeymapTest do
  @moduledoc """
  The keyhandling contract, tested as a pure reducer with no TTY (design §8: the cockpit's one
  brain, extracted from its paint). `Aleph.Keymap.handle/2` maps `(key_event, state)` to
  `{new_state, effect}`; the Cockpit interprets the effect (`:repaint` / `:quit` /
  `{:forward, key}` / `:none`). Every binding is asserted here so a regression like "arrow keys
  stopped moving focus" is caught headlessly.
  """
  use ExUnit.Case, async: true

  alias Aleph.Keymap

  # The slice of cockpit state the keymap reads. Threads are anything with an `.id`.
  defp state(overrides \\ %{}) do
    Map.merge(
      %{
        active_key: :sessions,
        focused_id: 2,
        threads: [%{id: 1}, %{id: 2}, %{id: 3}],
        center_focused?: false,
        input: nil
      },
      overrides
    )
  end

  defp key(k, opts \\ []), do: Enum.into(opts, %{key: k})
  defp char(c, opts \\ []), do: Enum.into(opts, %{key: :char, char: c})

  describe "quit" do
    test "q quits" do
      assert {_state, :quit} = Keymap.handle(char("q"), state())
    end

    test "Ctrl-C quits" do
      assert {_state, :quit} = Keymap.handle(char("c", ctrl: true), state())
    end
  end

  describe "space switching" do
    # Picker order: Comms · Sessions · Issues; the default state sits on Sessions.
    test "Tab moves to the next space and repaints" do
      assert {%{active_key: :issues}, :repaint} = Keymap.handle(key(:tab), state())
    end

    test "Shift-Tab moves to the previous space (wraps)" do
      assert {%{active_key: :issues}, :repaint} =
               Keymap.handle(key(:tab, shift: true), state(%{active_key: :comms}))
    end

    test "] is next, [ is previous" do
      assert {%{active_key: :issues}, :repaint} = Keymap.handle(char("]"), state())
      assert {%{active_key: :comms}, :repaint} = Keymap.handle(char("["), state())
    end

    test "switching a space leaves the center unfocused" do
      assert {%{center_focused?: false}, :repaint} =
               Keymap.handle(key(:tab), state(%{center_focused?: false}))
    end
  end

  describe "thread focus movement" do
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
  end

  describe "center focus (Enter / Ctrl+B leader)" do
    test "Enter focuses the center in the Sessions space" do
      assert {%{center_focused?: true}, :repaint} =
               Keymap.handle(key(:enter), state(%{active_key: :sessions}))
    end

    test "Enter does nothing outside the Sessions space" do
      s = state(%{active_key: :comms})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end

    test "the leader Ctrl+B releases center focus" do
      assert {%{center_focused?: false}, :repaint} =
               Keymap.handle(char("b", ctrl: true), state(%{center_focused?: true}))
    end

    test "Esc while focused FORWARDS to the pane — the app gets it, it never traps you in aleph" do
      s = state(%{center_focused?: true})
      assert {^s, {:forward, %{key: :escape}}} = Keymap.handle(key(:escape), s)
    end

    test "Ctrl+B when the center isn't focused is not a release (no-op locally)" do
      s = state(%{center_focused?: false})
      assert {^s, :none} = Keymap.handle(char("b", ctrl: true), s)
    end
  end

  describe "forwarding to the tmux pane while focused" do
    test "a printable key is forwarded, not acted on locally" do
      s = state(%{center_focused?: true})
      assert {^s, {:forward, %{key: :char, char: "q"}}} = Keymap.handle(char("q"), s)
    end

    test "Ctrl-C is forwarded to the pane, not a quit, while focused" do
      s = state(%{center_focused?: true})
      k = char("c", ctrl: true)
      assert {^s, {:forward, ^k}} = Keymap.handle(k, s)
    end

    test "arrows are forwarded while focused" do
      s = state(%{center_focused?: true})
      assert {^s, {:forward, %{key: :up}}} = Keymap.handle(key(:up), s)
    end

    test "Tab is forwarded while focused (shell completion), not a space switch" do
      s = state(%{center_focused?: true})
      assert {^s, {:forward, %{key: :tab}}} = Keymap.handle(key(:tab), s)
    end
  end

  describe "unknown keys" do
    test "an unbound key is a no-op" do
      s = state()
      assert {^s, :none} = Keymap.handle(key(:f5), s)
    end
  end

  describe "creating a thread — the `n` verb + title input mode" do
    test "n opens title input (empty buffer) and repaints" do
      assert {%{input: %{kind: :new_thread, buffer: ""}}, :repaint} = Keymap.handle(char("n"), state())
    end

    test "printable keys accumulate into the buffer, not acted on locally" do
      s = state(%{input: %{kind: :new_thread, buffer: "fab"}})
      assert {%{input: %{buffer: "fabl"}}, :repaint} = Keymap.handle(char("l"), s)
      # 'e' — normally nothing, here it's just text
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

  describe "spawning a session onto the focused thread — the `s` verb" do
    test "s asks to spawn onto the focused thread" do
      assert {_s, {:spawn, 2}} = Keymap.handle(char("s"), state())
    end

    test "s with no focused thread is a no-op" do
      s = state(%{focused_id: nil, threads: []})
      assert {^s, :none} = Keymap.handle(char("s"), s)
    end

    test "s is captured as text while typing a title, not a spawn" do
      s = state(%{input: %{kind: :new_thread, buffer: "clas"}})
      assert {%{input: %{buffer: "class"}}, :repaint} = Keymap.handle(char("s"), s)
    end
  end
end
