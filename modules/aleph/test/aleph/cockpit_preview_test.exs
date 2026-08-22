defmodule Aleph.CockpitPreviewTest do
  @moduledoc """
  The selection-driven center re-point (Worlds Slice 0, tweak #1): in Tlön nav mode a hover over a
  window-bearing pane (Leaves — each leaf maps to a live World tmux window by its lead) PREVIEWS
  that window in the center (`select-window` re-point, `previewed_window` stored) WITHOUT taking
  keyboard focus or sending keys; only a COMMIT (`commit_preview/1`) drops into the terminal.

  These exercise the pure state transforms the cockpit's `:tlon_preview`/commit paths run — the
  tmux runner is injected (`:aleph, :tlon_cmd`) so the argv is asserted without a live server, the
  same seam `Aleph.CrewTest` uses.
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

  # A Tlön nav state focused on the Leaves pane (right column, index 2 in the derived layout), the
  # item cursor on `row_idx`, keys NOT forwarding (in_terminal? false).
  defp leaves_state(rows, row_idx) do
    %{
      active_key: 0,
      focus: %Focus{in_terminal?: false, column: :right, pane: 2, cursors: %{Panel.Leaves => row_idx}},
      leaves: %{summary: %{}, rows: rows},
      stack: nil,
      memory: nil,
      previewed_window: nil
    }
  end

  describe "preview_focused/1 — hover re-points, never focuses" do
    test "a leaf mapped to a live World window re-points the center but stays in nav mode" do
      next = Cockpit.preview_focused(leaves_state([%{id: "t1", title: "x", lead: "hronir"}], 0))

      assert next.previewed_window == "1"
      # NO focus steal, NO keys sent — a hover, not a commit.
      assert next.focus.in_terminal? == false
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "tlon:1"]}
    end

    test "a leaf whose lead has no live window leaves the center where it is (no re-point)" do
      next = Cockpit.preview_focused(leaves_state([%{id: "t9", title: "x", lead: "ghost"}], 0))

      assert next.previewed_window == nil
      refute_received {:tmux, ["-L", _sock, "select-window" | _]}
    end

    test "outside Tlön it is a no-op" do
      state = %{active_key: :orbis, previewed_window: nil}
      assert Cockpit.preview_focused(state) == state
    end
  end

  describe "commit_preview/1 — commit takes focus into the previewed window" do
    test "sets in_terminal? true so keystrokes now flow" do
      next = Cockpit.commit_preview(%{leaves_state([%{id: "t1", lead: "hronir"}], 0) | previewed_window: "1"})
      assert next.focus.in_terminal? == true
    end
  end
end
