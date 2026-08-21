defmodule Aleph.CockpitLeavesAttachTest do
  @moduledoc """
  Leaves-Enter attach (Worlds Slice 0, Task 2): pressing Enter on a leaf whose lead maps to a live
  World tmux window ATTACHES that window in the center — PREVIEW (re-point) then COMMIT (focus in),
  reusing Task 1's `preview_focused/1` + `commit_preview/1`. A leaf with no live window can't attach
  yet (arbitrary-leaf PTYs are Slice 1) — it flashes the deferral and re-points nothing, never the
  old `active_key: :sessions` jump.

  These exercise `attach_leaf/2`, the pure decision the `:tlon_enter` → `jump_to_leaf` path runs
  before its (termbox-painting, un-unit-testable) render. The tmux runner is injected
  (`:aleph, :tlon_cmd`) so argv is asserted without a live server, the same seam the preview test
  uses. `previewed_window` is tmux's STRING window index (`"1"`), not an int.
  """
  use ExUnit.Case, async: false

  alias Aleph.Cockpit
  alias Aleph.Panel
  alias Aleph.Tlon.Focus

  setup do
    test_pid = self()

    # Fake tmux runner: records argv; `list-windows` reports three World windows
    # (tertius@0, hronir@1, uqbar@2), everything else (select-window) is a no-op success.
    Application.put_env(:aleph, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\ttertius\n0\t1\thronir\n0\t2\tuqbar\n", 0},
        else: {"", 0}
    end)

    on_exit(fn -> Application.delete_env(:aleph, :tlon_cmd) end)
    :ok
  end

  # A Tlön nav state focused on the Leaves pane (right column, index 2 — matches Space.fetch(:tlon)),
  # the item cursor on row 0, keys NOT forwarding (in_terminal? false).
  defp leaves_state(rows) do
    %{
      active_key: :tlon,
      focus: %Focus{in_terminal?: false, column: :right, pane: 2, cursors: %{Panel.Leaves => 0}},
      leaves: %{summary: %{}, rows: rows},
      stack: nil,
      memory: nil,
      flash: nil,
      previewed_window: nil
    }
  end

  # The right-column layout the cockpit derives for Tlön (Leaves at index 2), with the Leaves count
  # so the focus cursor resolves the row under it.
  defp leaves_layout(rows) do
    %{
      left: [Panel.Spaces, Panel.Stack, Panel.Memory],
      right: [Panel.Health, Panel.Activity, Panel.Leaves],
      sections: %{},
      counts: %{Panel.Leaves => length(rows)}
    }
  end

  describe "attach_leaf/2 — the Leaves-Enter decision" do
    test "a leaf mapped to a live World window attaches it: preview (string index) + commit (focus)" do
      rows = [%{id: "t1", title: "x", lead: "hronir"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.previewed_window == "1"
      assert next.focus.in_terminal? == true
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "tlon:1"]}
      # Retargeted off the deleted Sessions space — no space switch.
      refute Map.get(next, :active_key) == :sessions
    end

    test "a leaf with no live window flashes the Slice-1 deferral, re-points nothing, no crash" do
      rows = [%{id: "t9", title: "x", lead: "ghost"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.flash =~ "no live session"
      assert next.previewed_window == nil
      assert next.focus.in_terminal? == false
      refute_received {:tmux, ["-L", _sock, "select-window" | _]}
    end

    test "no leaf under the cursor (empty rollup) also flashes, never crashes" do
      next = Cockpit.attach_leaf(leaves_state([]), leaves_layout([]))
      assert next.flash =~ "no live session"
      assert next.previewed_window == nil
    end
  end
end
