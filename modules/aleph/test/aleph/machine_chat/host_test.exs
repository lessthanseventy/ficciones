defmodule Aleph.MachineChat.HostTest do
  use ExUnit.Case, async: true

  alias Aleph.MachineChat.Host

  defp block(id), do: %{thread: %{id: id, title: "t#{id}"}, messages: []}

  describe "merge/2 — folding across polls" do
    test "every thread is folded by default — the chat opens as a compact episode list" do
      state = Host.merge(Host.new(), [block(3), block(2), block(1)])

      assert MapSet.member?(state.folded, 3)
      assert MapSet.member?(state.folded, 2)
      assert MapSet.member?(state.folded, 1)
    end

    test "a manually-expanded old thread stays expanded when a new thread arrives" do
      state =
        Host.new()
        |> Host.merge([block(2), block(1)])
        # select the older thread (index 1) and manually expand it
        |> Host.handle_key(:down)
        |> Host.handle_key(:toggle)

      refute MapSet.member?(state.folded, 1)

      # a newer thread arrives; thread 1 slides to the bottom but the manual expand must persist
      state = Host.merge(state, [block(3), block(2), block(1)])

      refute MapSet.member?(state.folded, 1)
    end

    test "selection is clamped when the block list shrinks" do
      state =
        Host.new()
        |> Host.merge([block(3), block(2), block(1)])
        |> Host.handle_key(:down)
        |> Host.handle_key(:down)

      assert state.selected == 2

      state = Host.merge(state, [block(3)])
      assert state.selected == 0
    end

    test "zoom is cleared when the zoomed thread disappears, kept when it survives" do
      zoomed = Host.new() |> Host.merge([block(2), block(1)]) |> Host.handle_key(:zoom)
      assert zoomed.zoom == 2

      assert Host.merge(zoomed, [block(2), block(1)]).zoom == 2
      assert Host.merge(zoomed, [block(1)]).zoom == nil
    end
  end

  describe "handle_key/2" do
    setup do
      %{state: Host.merge(Host.new(), [block(3), block(2), block(1)])}
    end

    test ":down and :up move the selection, clamped to the ends", %{state: state} do
      assert Host.handle_key(state, :up).selected == 0

      state = state |> Host.handle_key(:down) |> Host.handle_key(:down) |> Host.handle_key(:down)
      assert state.selected == 2
    end

    test ":toggle unfolds and re-folds the selected block", %{state: state} do
      # every block starts folded (the compact list), so the first toggle expands the selection
      unfolded = Host.handle_key(state, :toggle)
      refute MapSet.member?(unfolded.folded, 3)

      refolded = Host.handle_key(unfolded, :toggle)
      assert MapSet.member?(refolded.folded, 3)
    end

    test ":toggle is a no-op while zoomed", %{state: state} do
      zoomed = Host.handle_key(state, :zoom)
      assert Host.handle_key(zoomed, :toggle) == zoomed
    end

    test ":zoom targets the selected thread and :back clears it", %{state: state} do
      zoomed = state |> Host.handle_key(:down) |> Host.handle_key(:zoom)
      assert zoomed.zoom == 2

      assert Host.handle_key(zoomed, :back).zoom == nil
    end

    test ":quit sets the quit flag", %{state: state} do
      assert Host.handle_key(state, :quit).quit
    end
  end
end
