defmodule Funes.Workline do
  @moduledoc """
  The workline stage machine (worklines slice 1, design:
  `docs/plans/2026-08-27-ai-native-sdlc-workline-design.md`). A workline is a thread paired
  with a git folder `work/<slug>/`; its thread carries the stage:

      intent → spec → plan → build → verify → review → merged

  `advance/2` is the single mutation point and carries the invariant: NO advance without the
  stage's owed artifact (checked through the `Funes.Workline.Artifacts` behaviour, recorded
  as a CHECK either way, correlation `workline:<slug>:artifact`). Gated transitions —
  spec→plan, review→merged, and a machine-born intent→spec — park in `awaiting: "andrew"`
  instead of flipping; `approve/1` is the operator's completion verb. Every completed flip
  records a `stage_advanced` event: the slice-6 ledger reads metrics out of rows that
  already exist.
  """

  alias Funes.Dossier
  alias Funes.Repo
  alias Funes.Thread

  @stages ~w(intent spec plan build verify review merged)
  @owed %{
    "intent" => {:file, "intent.md"},
    "spec" => {:file, "spec.md"},
    "plan" => {:file, "plan.md"},
    "build" => :branch,
    "verify" => :checks,
    "review" => {:file, "review.md"}
  }
  # Stages whose EXIT waits on the operator; a machine-born intent gates its exit too.
  @gated ~w(spec review)

  @doc "The stage ring, first to terminal."
  def stages, do: @stages

  @doc """
  Open a workline: a machine-scoped thread at stage "intent" + the `work/<slug>/` name.
  `{:ok, thread}` or `{:error, changeset}` (a taken slug is a UNIQUE refusal).
  """
  def open(attrs) do
    attrs |> Thread.workline_changeset() |> Repo.insert() |> Funes.Bus.announce(:thread_opened)
  end

  @doc """
  Advance past the current stage. `{:ok, thread}` on a flip, `{:awaiting, thread}` when the
  transition gates on the operator, `{:error, {:artifact_missing, why}}` when the owed
  artifact isn't committed, `{:error, :awaiting_operator | :terminal | :not_a_workline}`
  otherwise. `opts[:artifacts]` swaps the checker (tests stub it; default is git).
  """
  def advance(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Funes.Workline.Artifacts.Git)

    with :ok <- advanceable(thread),
         :ok <- verified_artifact(thread, checker) do
      if gated?(thread), do: park(thread), else: flip(thread)
    end
  end

  @doc """
  Complete a parked gate — the operator's verb (funes-cli `approve` today; the cockpit
  surface lands in slice 2). `{:ok, thread}` or `{:error, :nothing_awaiting}`.
  """
  def approve(%Thread{awaiting: awaiting} = thread) when not is_nil(awaiting) do
    {:ok, cleared} = thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()
    flip(cleared)
  end

  def approve(%Thread{}), do: {:error, :nothing_awaiting}

  defp advanceable(%Thread{stage: nil}), do: {:error, :not_a_workline}
  defp advanceable(%Thread{stage: "merged"}), do: {:error, :terminal}
  defp advanceable(%Thread{awaiting: awaiting}) when not is_nil(awaiting), do: {:error, :awaiting_operator}
  defp advanceable(%Thread{}), do: :ok

  # The owed-artifact check, recorded as a CHECK either way — the audit half of the invariant.
  defp verified_artifact(thread, checker) do
    requirement = Map.fetch!(@owed, thread.stage)

    case checker.check(thread, requirement) do
      {:ok, evidence} ->
        record_artifact_check(thread, requirement, 0, evidence)
        :ok

      {:error, why} ->
        record_artifact_check(thread, requirement, 1, why)
        {:error, {:artifact_missing, why}}
    end
  end

  defp record_artifact_check(thread, requirement, exit_code, tail) do
    Dossier.record_check(%{
      thread_id: thread.id,
      cmd: "workline artifact #{describe(requirement)}",
      exit: exit_code,
      tail: tail,
      correlation: "workline:#{thread.slug}:artifact"
    })
  end

  defp describe({:file, name}), do: name
  defp describe(other), do: to_string(other)

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

  defp park(thread) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
    Funes.Bus.broadcast({:workline_gated, parked})
    {:awaiting, parked}
  end

  defp flip(thread) do
    to = next(thread.stage)
    {:ok, flipped} = thread |> Thread.workline_stage_changeset(%{stage: to}) |> Repo.update()

    Dossier.record_event(%{
      thread_id: thread.id,
      kind: "stage_advanced",
      correlation: "workline:#{thread.slug}",
      detail: %{"from" => thread.stage, "to" => to}
    })

    Funes.Bus.broadcast({:workline_advanced, flipped})
    {:ok, flipped}
  end

  defp next(stage), do: Enum.at(@stages, Enum.find_index(@stages, &(&1 == stage)) + 1)
end
