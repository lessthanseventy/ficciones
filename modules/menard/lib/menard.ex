defmodule Menard do
  @moduledoc """
  Menard — Pierre Menard, author of the Quixote: rewrite a text word for word and have it come
  out different. AST-aware edits and introspection for Elixir repos (Sourceror patches: only the
  bytes a verb names move), as a project of its own so `mix menard.*` runs even while the app
  being edited does not compile. Design: `docs/plans/2026-09-08-elixir-repo-tools-design.md`.

  The tasks run from THIS project (`mise run menard -- …` from anywhere in the repo), so a path is
  resolved against the caller's directory (`MISE_ORIGINAL_CWD`, else the cwd), and the run/inspect
  verbs act in `--in DIR` (default: the caller's directory).
  """

  @doc "The directory the caller stood in."
  def caller_dir, do: System.get_env("MISE_ORIGINAL_CWD") || File.cwd!()

  @doc "A path as the caller meant it: absolute stays, relative joins the caller's directory."
  def resolve(path), do: Path.expand(path, caller_dir())

  @doc """
  Format `file` with the TARGET project's formatter: `mix format` from the nearest ancestor holding a
  `.formatter.exs` (else a `mix.exs`, else the file's own directory). Run from the file's own directory
  — `lib/menard/` has no config — mix falls back to the DEFAULT line length and reflows the whole
  file: a one-clause edit came back as a 39-line diff, the opposite of what these verbs promise.
  """
  def format(file) do
    System.cmd("mix", ["format", file], cd: formatter_root(file), stderr_to_stdout: true)
    :ok
  end

  defp formatter_root(file) do
    dir = file |> Path.expand() |> Path.dirname()
    find_up(dir, ".formatter.exs") || find_up(dir, "mix.exs") || dir
  end

  defp find_up("/", _name), do: nil

  defp find_up(dir, name) do
    if File.exists?(Path.join(dir, name)), do: dir, else: find_up(Path.dirname(dir), name)
  end
end
