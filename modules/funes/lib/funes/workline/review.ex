defmodule Funes.Workline.Review do
  @moduledoc """
  The reviewer's ONE door (worklines slice 3). The reviewer profile is structurally
  write-fenced (@reviewer_permissions denies write/edit + bash redirects), so review.md
  cannot be hand-written — `submit/3` is the single sanctioned path: funes writes
  `work/<slug>/review.md` in the workline root and commits it. The fence stays airtight;
  a hook, not an advisory.
  """

  alias Funes.Thread
  alias Funes.Workline.Artifacts

  @doc """
  Write + commit the review verdict. `{:ok, rel_path}`, `{:error, {:not_in_review, stage}}`
  outside the review stage, or `{:error, reason}` on a git fault. Identical resubmission is
  `{:ok, _}` — the artifact is already committed, which is the point.
  """
  def submit(%Thread{stage: "review", slug: slug}, body, author) when is_binary(body) do
    root = Artifacts.Git.root()
    rel = Path.join(["work", slug, "review.md"])
    abs = Path.join(root, rel)

    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, body)

    with {_, 0} <- git(root, ["add", rel]),
         :ok <- commit(root, rel, slug, author) do
      {:ok, rel}
    else
      {out, _code} -> {:error, "git refused: #{String.slice(out, 0, 200)}"}
      {:error, _} = error -> error
    end
  end

  def submit(%Thread{stage: stage}, _body, _author), do: {:error, {:not_in_review, stage}}

  # Identical content → nothing staged → skip the commit; the artifact is already in history.
  defp commit(root, rel, slug, author) do
    case git(root, ["status", "--porcelain", "--", rel]) do
      {"", 0} ->
        :ok

      {_dirty, 0} ->
        case git(root, ["commit", "-m", "workline #{slug}: review verdict (submit_review by #{author})", "--", rel]) do
          {_, 0} -> :ok
          {out, _} -> {:error, "git commit refused: #{String.slice(out, 0, 200)}"}
        end

      {out, _} ->
        {:error, "git status refused: #{String.slice(out, 0, 200)}"}
    end
  end

  defp git(root, args), do: System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
end
