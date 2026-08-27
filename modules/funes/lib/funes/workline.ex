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
  alias Funes.Workline.Brief

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

  # The ring, the owed map, and the gate list drift independently unless something ties them:
  # every non-terminal stage MUST owe an artifact, every gated stage must be in the ring.
  for stage <- Enum.drop(@stages, -1) do
    Map.has_key?(@owed, stage) || raise "stage #{stage} has no owed artifact in @owed"
  end

  for stage <- @gated do
    stage in @stages || raise "gated stage #{stage} is not in @stages"
  end

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
  defp advanceable(%Thread{stage: stage}) when stage in @stages, do: :ok
  # A stage outside the ring (hand-edited row, drifted data) is a typed refusal, not a crash.
  defp advanceable(%Thread{stage: stage}), do: {:error, {:invalid_stage, stage}}

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
      # Stage-suffixed so the ledger can filter per-stage history on the indexed column.
      correlation: "workline:#{thread.slug}:artifact:#{thread.stage}"
    })
  end

  defp describe({:file, name}), do: name
  defp describe(other), do: to_string(other)

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

  defp park(thread) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
    Funes.Bus.broadcast({:workline_gated, parked})
    post_brief(parked, Brief.gate_message(parked))
    {:awaiting, parked}
  end

  # One transaction: the stage flip and its ledger row commit together or not at all.
  defp flip(thread) do
    to = next(thread.stage)

    {:ok, flipped} =
      Repo.transaction(fn ->
        {:ok, flipped} = thread |> Thread.workline_stage_changeset(%{stage: to}) |> Repo.update()

        {:ok, _event} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "stage_advanced",
            correlation: "workline:#{thread.slug}",
            detail: %{"from" => thread.stage, "to" => to}
          })

        flipped
      end)

    Funes.Bus.broadcast({:workline_advanced, flipped})
    flipped = if flipped.stage == "review", do: restaff_reviewer(flipped), else: flipped
    post_brief(flipped, Brief.stage_message(flipped))
    {:ok, flipped}
  end

  # Entering review: the world's reviewer takes the lead — the builder never approves its own
  # work by proxy. Best-effort: no world / no reviewer archetype / unregistered handle → the
  # current lead stands and the brief still lands.
  defp restaff_reviewer(%Thread{world_id: nil} = thread), do: thread

  defp restaff_reviewer(thread) do
    with %{roster: roster} when is_list(roster) <- Repo.get(Funes.World, thread.world_id),
         %{"name" => name} <- Enum.find(roster, &(&1["archetype"] == "reviewer" || &1[:archetype] == "reviewer")),
         {:ok, restaffed} <- Funes.Channel.assign_lead(thread.id, "#{name}-machine") do
      post_brief(restaffed, "→ #{name}-machine leads (review stage)")
      restaffed
    else
      _ -> thread
    end
  end

  # The brief IS the wake: a funes-authored message rides the lead-wake path (slice 2).
  # Best-effort — a post failure never blocks the (already durable) transition.
  defp post_brief(thread, body) do
    Funes.Channel.post(%{thread_id: thread.id, author: "funes", body: body})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp next(stage), do: Enum.at(@stages, Enum.find_index(@stages, &(&1 == stage)) + 1)
end
