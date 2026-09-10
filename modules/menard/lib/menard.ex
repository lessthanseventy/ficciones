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
  @format_timeout 30_000

  def caller_dir, do: System.get_env("MISE_ORIGINAL_CWD") || File.cwd!()

  @doc "A path as the caller meant it: absolute stays, relative joins the caller's directory."
  def resolve(path), do: Path.expand(path, caller_dir())

  @doc """
  Format `file` with the TARGET project's formatter: `mix format` from the nearest ancestor holding
  a `.formatter.exs` (else a `mix.exs`, else the file's own directory). Run from the file's own
  directory — `lib/menard/` has no config — mix falls back to the DEFAULT line length and reflows the
  whole file: a one-clause edit came back as a 39-line diff, the opposite of what these verbs promise.

  BOUNDED, because this shells out: `mix` can block on the build lock, on a mise shim resolving a
  toolchain, or on a project that will not load. An unbounded wait hangs the CALLER — over stdio that
  is an MCP tool which never answers at all. `{:error, reason}` after the timeout degrades to "written
  but not formatted", which a caller can report; a hang is not.
  """
  def format(file) do
    task =
      Task.async(fn ->
        System.cmd("mix", ["format", file], cd: formatter_root(file), stderr_to_stdout: true)
      end)

    case Task.yield(task, @format_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, _output} ->
        :ok

      _timeout ->
        {:error, "mix format did not finish in #{div(@format_timeout, 1000)}s — file written UNFORMATTED"}
    end
  end

  defp formatter_root(file) do
    dir = file |> Path.expand() |> Path.dirname()
    find_up(dir, ".formatter.exs") || find_up(dir, "mix.exs") || dir
  end

  defp find_up("/", _name), do: nil

  defp find_up(dir, name) do
    if File.exists?(Path.join(dir, name)), do: dir, else: find_up(Path.dirname(dir), name)
  end

  @doc """
  Write `content` to `file`, but only if it still parses as Elixir, then format it. Every edit verb
  goes through here: an AST patch that lands unparseable bytes locks the file out of every other
  verb, and text editing is then the only door back.
  """
  @spec checked_write(String.t(), String.t()) :: :ok | {:error, String.t()}
  def checked_write(file, content) do
    case Menard.Write.checked(file, content) do
      {:ok, checked} ->
        File.write!(file, checked)
        # A format timeout is NOT a write failure: the bytes are on disk and correct, just not
        # reformatted. Say so rather than failing an edit that actually landed.
        case format(file) do
          :ok -> :ok
          {:error, reason} -> Mix.shell().error("menard: " <> reason)
        end

        :ok

      {:error, reason} ->
        {:error, "refusing to write #{Path.relative_to_cwd(file)} — #{reason}"}
    end
  end
end
