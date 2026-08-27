defmodule Funes.Workline.Artifacts do
  @moduledoc """
  The owed-artifact checker seam: is the stage's exit evidence really there? Requirements:
  `{:file, name}` (committed under `work/<slug>/`), `:branch` (the workline branch exists),
  `:checks` (verify-stage evidence — a `check_passed` correlated `workline:<slug>:verify`).
  A behaviour so the stage machine tests with stubs and the git impl stays one module.
  """

  @callback check(Funes.Thread.t(), {:file, String.t()} | :branch | :checks) ::
              {:ok, String.t()} | {:error, String.t()}
end

defmodule Funes.Workline.Artifacts.Git do
  @moduledoc """
  The real checker: files must be COMMITTED (git ls-files, not mere existence — an untracked
  intent.md is not an artifact), the branch is `work/<slug>`, verify evidence is a
  `check_passed` event correlated `workline:<slug>:verify`. Repo root comes from
  `config :funes, :workline_root` (the world's git tree), default cwd.
  """

  @behaviour Funes.Workline.Artifacts

  import Ecto.Query

  alias Funes.Event
  alias Funes.Repo

  @impl true
  def check(thread, {:file, name}) do
    rel = Path.join(["work", thread.slug, name])

    case git(["ls-files", "--error-unmatch", rel]) do
      {_out, 0} -> {:ok, "committed #{rel}"}
      {_out, _} -> {:error, "#{rel} is not committed"}
    end
  end

  def check(thread, :branch) do
    branch = "work/#{thread.slug}"

    case git(["rev-parse", "--verify", "--quiet", branch]) do
      {sha, 0} -> {:ok, "#{branch} @ #{String.slice(String.trim(sha), 0, 12)}"}
      {_out, _} -> {:error, "branch #{branch} does not exist"}
    end
  end

  def check(thread, :checks) do
    correlation = "workline:#{thread.slug}:verify"

    passed =
      Repo.exists?(
        from e in Event,
          where: e.thread_id == ^thread.id and e.kind == "check_passed" and e.correlation == ^correlation
      )

    if passed,
      do: {:ok, "verify evidence recorded (#{correlation})"},
      else: {:error, "no check_passed correlated #{correlation}"}
  end

  defp git(args), do: System.cmd("git", ["-C", root() | args], stderr_to_stdout: true)

  defp root, do: Application.get_env(:funes, :workline_root) || File.cwd!()
end
