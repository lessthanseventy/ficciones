defmodule Aleph.Panel.SettingsTest do
  @moduledoc "The SETTINGS panel: effective driver, the ring with the current entry marked, honest apply note."
  use ExUnit.Case, async: true

  alias Aleph.Panel.Settings

  @rect %{x: 0, y: 0, w: 60, h: 20}

  @data %{
    profile: "tlon",
    model: %{provider: "anthropic", model: "claude-sonnet-5", thinking: "medium"},
    ring: [
      %{provider: "anthropic", model: "claude-sonnet-5", thinking: "medium"},
      %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}
    ],
    override?: false
  }

  defp text(rows), do: Enum.map_join(rows, "\n", fn runs -> Enum.map_join(runs, "", &elem(&1, 0)) end)

  test "shows the effective driver and which ring entry is current" do
    out = text(Settings.render(@data, @rect))
    assert out =~ "SETTINGS"
    assert out =~ "coworker tlon"
    assert out =~ "driver anthropic/claude-sonnet-5"
    assert out =~ "● anthropic/claude-sonnet-5"
    assert out =~ "○ ollama-cloud/glm-5.2"
  end

  test "is honest that a change applies on respawn, not to the running session" do
    assert text(Settings.render(@data, @rect)) =~ "applies on respawn"
  end

  test "an override is labelled as coming from the settings file" do
    assert text(Settings.render(%{@data | override?: true}, @rect)) =~ "(set here)"
    refute text(Settings.render(@data, @rect)) =~ "(set here)"
  end

  test "nil data (a space with no coworker) renders nothing" do
    assert Settings.render(nil, @rect) == []
  end
end
