defmodule Aleph.Panel.SettingsModalTest do
  @moduledoc "The settings modal body: per-coworker driver ring + permission policy, with the selected knob marked."
  use ExUnit.Case, async: true

  alias Aleph.Panel.SettingsModal

  @rect %{x: 0, y: 0, w: 60, h: 30}

  @glm %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}
  @kimi %{provider: "ollama-cloud", model: "kimi-k2.7-code", thinking: "medium"}

  defp row(overrides \\ %{}) do
    Map.merge(%{profile: "tertius", model: @glm, ring: [@glm, @kimi], override?: false, yolo?: true}, overrides)
  end

  defp data(overrides \\ %{}) do
    Map.merge(%{row: 0, field: :model, rows: [row()]}, overrides)
  end

  defp text(rows), do: Enum.map_join(rows, "\n", fn runs -> Enum.map_join(runs, "", &elem(&1, 0)) end)

  test "shows the coworker, its effective driver, the ring, and the permission policy" do
    out = text(SettingsModal.render(data(), @rect))
    assert out =~ "SETTINGS"
    assert out =~ "tertius"
    assert out =~ "driver ollama-cloud/glm-5.2"
    assert out =~ "● ollama-cloud/glm-5.2"
    assert out =~ "○ ollama-cloud/kimi-k2.7-code"
    assert out =~ "perms  yolo (auto-approve asks)"
  end

  test "the ▸ marker sits on the driver line when the model knob is selected" do
    rows = SettingsModal.render(data(%{field: :model}), @rect)
    driver_row = Enum.find(rows, fn r -> text([r]) =~ "driver ollama" end)
    assert text([driver_row]) =~ "▸"
  end

  test "the ▸ marker moves to the permission line when the permission knob is selected" do
    rows = SettingsModal.render(data(%{field: :permission}), @rect)
    perms_row = Enum.find(rows, fn r -> text([r]) =~ "perms" end)
    driver_row = Enum.find(rows, fn r -> text([r]) =~ "driver ollama" end)
    assert text([perms_row]) =~ "▸"
    refute text([driver_row]) =~ "▸"
  end

  test "yolo? false renders the ask policy" do
    assert text(SettingsModal.render(data(%{rows: [row(%{yolo?: false})]}), @rect)) =~ "perms  ask (human answers)"
  end

  test "an overridden driver is labelled (set here)" do
    assert text(SettingsModal.render(data(%{rows: [row(%{override?: true})]}), @rect)) =~ "(set here)"
  end

  test "height/1 counts the rows it renders — the View sizes the box to it" do
    assert SettingsModal.height(data()) == length(SettingsModal.render(data(), %{@rect | h: 10_000}))
  end

  test "nil data renders nothing" do
    assert SettingsModal.render(nil, @rect) == []
  end
end
