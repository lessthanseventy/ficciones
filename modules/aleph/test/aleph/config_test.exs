defmodule Aleph.ConfigTest do
  @moduledoc "The operator settings file: best-effort reads, atomic writes, the coworker-model knob."
  use ExUnit.Case, async: true

  alias Aleph.Config

  setup do
    dir = Path.join(System.tmp_dir!(), "aleph-config-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{path: Path.join(dir, "config.json")}
  end

  test "an absent file is no overrides, not a crash", %{path: path} do
    assert Config.read(path) == %{}
    assert Config.coworker_model("tlon", path) == nil
  end

  test "a corrupt file is no overrides (defaults win), never a crash", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{not json")
    assert Config.read(path) == %{}
  end

  test "put_coworker_model persists and reads back in the Profile.model shape", %{path: path} do
    :ok = Config.put_coworker_model("tlon", %{provider: "anthropic", model: "claude-opus-4-8", thinking: "medium"}, path)

    assert Config.coworker_model("tlon", path) ==
             %{provider: "anthropic", model: "claude-opus-4-8", thinking: "medium"}
  end

  test "a second put replaces the first without disturbing other profiles", %{path: path} do
    :ok = Config.put_coworker_model("tlon", %{provider: "anthropic", model: "claude-sonnet-5", thinking: "medium"}, path)
    :ok = Config.put_coworker_model("desk", %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}, path)
    :ok = Config.put_coworker_model("tlon", %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}, path)

    assert Config.coworker_model("tlon", path).model == "glm-5.2"
    assert Config.coworker_model("desk", path).model == "glm-5.2"
  end

  test "a missing thinking key defaults to medium (hand-edited file tolerated)", %{path: path} do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, ~s({"coworkers":{"tlon":{"provider":"anthropic","model":"claude-opus-4-8"}}}))
    assert Config.coworker_model("tlon", path).thinking == "medium"
  end
end
