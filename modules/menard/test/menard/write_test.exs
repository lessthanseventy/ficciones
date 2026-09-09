defmodule Menard.WriteTest do
  # The whole-file verb — what the clause verbs structurally cannot be: a new module has no clause
  # to address and no file to patch. Its one job beyond writing bytes is refusing bytes that do
  # not parse, so a syntax error never reaches disk.
  use ExUnit.Case, async: true

  alias Menard.Write

  setup do
    dir = Path.join(System.tmp_dir!(), "menard-write-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "creates a new module, making the directory on the way", %{dir: dir} do
    path = Path.join([dir, "nested", "a.ex"])
    assert {:ok, :created} = Write.run(path, "defmodule A do\n  def go, do: 1\nend")
    assert File.read!(path) =~ "def go, do: 1"
  end

  test "replaces an existing file and reports which it did", %{dir: dir} do
    path = Path.join(dir, "a.ex")
    assert {:ok, :created} = Write.run(path, "defmodule A do\nend")
    assert {:ok, :replaced} = Write.run(path, "defmodule B do\nend")
    assert File.read!(path) =~ "defmodule B"
  end

  test "identical bytes are :unchanged, so nothing is rewritten or reformatted", %{dir: dir} do
    path = Path.join(dir, "a.ex")
    code = "defmodule A do\nend\n"
    assert {:ok, :created} = Write.run(path, code)
    assert {:ok, :unchanged} = Write.run(path, code)
  end

  test "refuses Elixir that does not parse, before it reaches disk", %{dir: dir} do
    path = Path.join(dir, "a.ex")
    assert {:error, message} = Write.run(path, "defmodule A do\n  def go, do: (\nend")
    assert message =~ "not parseable"
    refute File.exists?(path)
  end

  test "a non-Elixir file is written as-is — menard writes fixtures too", %{dir: dir} do
    path = Path.join(dir, "fixture.json")
    assert {:ok, :created} = Write.run(path, ~s({"not": "elixir"}))
    assert File.read!(path) =~ ~s("not")
  end

  test "always ends with exactly one trailing newline", %{dir: dir} do
    path = Path.join(dir, "a.ex")
    Write.run(path, "defmodule A do\nend")
    assert String.ends_with?(File.read!(path), "end\n")
  end
end
