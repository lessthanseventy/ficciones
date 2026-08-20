defmodule Aleph.Tlon.SettingsTest do
  @moduledoc "The Tlön settings modal: a pure reducer over which coworker row + which knob is selected."
  use ExUnit.Case, async: true

  alias Aleph.Tlon.Settings

  test "new/1 is closed, on the first coworker row, model knob" do
    s = Settings.new(["tertius", "hronir"])
    refute s.open?
    assert Settings.target(s) == {"tertius", :model}
  end

  test "open/1 shows it; close/1 hides it (state otherwise preserved)" do
    s = ["tertius"] |> Settings.new() |> Settings.open()
    assert s.open?
    refute Settings.close(s).open?
  end

  test "row_next / row_prev wrap within the coworker list" do
    s = ["tertius", "hronir", "uqbar"] |> Settings.new() |> Settings.open()

    assert s |> Settings.handle(:row_next) |> Settings.target() == {"hronir", :model}
    assert s |> Settings.handle(:row_next) |> Settings.handle(:row_next) |> Settings.target() == {"uqbar", :model}
    # wraps forward off the end back to the top
    assert 1..3
           |> Enum.reduce(s, fn _, acc -> Settings.handle(acc, :row_next) end)
           |> Settings.target() == {"tertius", :model}

    # wraps backward off the top to the bottom
    assert s |> Settings.handle(:row_prev) |> Settings.target() == {"uqbar", :model}
  end

  test "field_next toggles the selected knob model <-> permission, keeping the row" do
    s = ["tertius", "hronir"] |> Settings.new() |> Settings.open() |> Settings.handle(:row_next)

    on_perm = Settings.handle(s, :field_next)
    assert Settings.target(on_perm) == {"hronir", :permission}
    # toggles back to model
    assert on_perm |> Settings.handle(:field_next) |> Settings.target() == {"hronir", :model}
  end

  test "a single-coworker list: row nav is a no-op, never crashes" do
    s = ["tertius"] |> Settings.new() |> Settings.open()
    assert s |> Settings.handle(:row_next) |> Settings.target() == {"tertius", :model}
    assert s |> Settings.handle(:row_prev) |> Settings.target() == {"tertius", :model}
  end

  describe "next_yolo/1 — the permission toggle decision (total, never raises)" do
    test "yoloMode true flips to ask" do
      assert Settings.next_yolo(%{"yoloMode" => true}) == {:ok, false, "ask"}
    end

    test "yoloMode false flips to yolo" do
      assert {:ok, true, "yolo" <> _} = Settings.next_yolo(%{"yoloMode" => false})
    end

    test "a permissions map WITHOUT yoloMode reads as ask, flips to yolo — never crashes on `not nil`" do
      assert {:ok, true, "yolo" <> _} = Settings.next_yolo(%{"permission" => %{}})
    end

    test "nil permissions has no policy to toggle" do
      assert Settings.next_yolo(nil) == :no_policy
    end
  end
end
