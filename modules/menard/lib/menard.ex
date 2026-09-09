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
end
