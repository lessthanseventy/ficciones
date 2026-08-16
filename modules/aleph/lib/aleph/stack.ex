defmodule Aleph.Stack do
  @moduledoc """
  The machine/stack read models for the **Tlön** space (§the meta lens): what's changed in the env
  (recent `ficciones` commits — the stack's own changelog) and what's installed (tool versions).
  Best-effort and honest: a missing `git` or tool yields an empty/`"?"` value, never a crash. Tool
  versions are cached in `:persistent_term` (they don't change mid-session); commits are read fresh.
  """
  @default_tools [
    {"pi", ["--version"]},
    {"claude", ["--version"]},
    {"nix", ["--version"]},
    {"mise", ["--version"]},
    {"tmux", ["-V"]}
  ]

  @doc "Recent `ficciones` commits as `[%{hash, subject}]`, newest first (best-effort, fresh)."
  def commits(dir \\ ".", n \\ 8) do
    case cmd("git", ["-C", dir, "log", "--oneline", "-n", Integer.to_string(n)]) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> Enum.map(&parse_commit/1)
      :error -> []
    end
  end

  @doc "Installed tool versions as `[%{name, version}]`, cached after the first probe."
  def tools do
    case :persistent_term.get({__MODULE__, :tools}, nil) do
      nil ->
        probed = Enum.map(@default_tools, fn {name, args} -> %{name: name, version: version(name, args)} end)
        :persistent_term.put({__MODULE__, :tools}, probed)
        probed

      cached ->
        cached
    end
  end

  defp parse_commit(line) do
    case String.split(line, " ", parts: 2) do
      [hash, subject] -> %{hash: hash, subject: subject}
      [hash] -> %{hash: hash, subject: ""}
    end
  end

  # First non-empty line of the tool's version output, or "?" if it isn't installed / errored.
  defp version(name, args) do
    case cmd(name, args) do
      {:ok, out} -> out |> String.split("\n", trim: true) |> List.first() |> to_string() |> String.trim()
      :error -> "?"
    end
  end

  defp cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end
end
