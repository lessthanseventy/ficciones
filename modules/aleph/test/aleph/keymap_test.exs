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
        center_focused?: false
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

  describe "center focus (Enter / Esc)" do
    test "Enter focuses the center in the Sessions space" do
      assert {%{center_focused?: true}, :repaint} =
               Keymap.handle(key(:enter), state(%{active_key: :sessions}))
    end

    test "Enter does nothing outside the Sessions space" do
      s = state(%{active_key: :comms})
      assert {^s, :none} = Keymap.handle(key(:enter), s)
    end

    test "Esc releases center focus" do
      assert {%{center_focused?: false}, :repaint} =
               Keymap.handle(key(:escape), state(%{center_focused?: true}))
    end

    test "Esc when the center isn't focused is a no-op" do
      s = state(%{center_focused?: false})
      assert {^s, :none} = Keymap.handle(key(:escape), s)
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
end
