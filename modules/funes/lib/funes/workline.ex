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
  alias Funes.Workline.Artifacts.Git
  alias Funes.Workline.Brief
  alias Funes.Workline.Scribe

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
    with {:ok, thread} <-
           attrs |> Thread.workline_changeset() |> Repo.insert() |> Funes.Bus.announce(:thread_opened) do
      # The brief IS the wake from stage one — the intent playbook must not wait for an advance.
      post_brief(thread, Brief.stage_message(thread))
      {:ok, thread}
    end
  end

  @doc """
  Advance past the current stage. `{:ok, thread}` on a flip, `{:awaiting, thread}` when the
  transition gates on the operator, `{:error, {:artifact_missing, why}}` when the owed
  artifact isn't committed, `{:error, :awaiting_operator | :terminal | :not_a_workline}`
  otherwise. `opts[:artifacts]` swaps the checker (tests stub it; default is git).
  """
  def advance(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Git)

    with :ok <- advanceable(thread),
         :ok <- verified_artifact(thread, checker) do
      if gated?(thread), do: park(thread), else: flip(thread)
    end
  end

  @doc """
  Complete a parked gate — the operator's verb (funes-cli `approve`). RE-VERIFIES the owed
  artifact before flipping: a flag-parked intent (or an artifact that vanished since the
  park) cannot ride approval past the invariant. `{:ok, thread}`,
  `{:error, {:artifact_missing, why}}` (still parked), or `{:error, :nothing_awaiting}`.
  """
  def approve(thread, opts \\ [])

  def approve(%Thread{awaiting: awaiting} = thread, opts) when not is_nil(awaiting) do
    checker = Keyword.get(opts, :artifacts, Git)

    # A machine-born intent's approval IS its acceptance: funes materializes intent.md from
    # the breach evidence so the chain stays intact and approve stays one verb. Only against
    # the REAL checker — a test stub must never make funes commit into the live repo.
    if thread.stage == "intent" and thread.born == "machine" and checker == Git do
      Scribe.materialize_intent(thread)
    end

    with :ok <- verified_artifact(thread, checker) do
      {:ok, cleared} = thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()
      flip(cleared)
    end
  end

  def approve(%Thread{}, _opts), do: {:error, :nothing_awaiting}

  @doc """
  The Maintain back-edge's verb: open a MACHINE-BORN workline already parked at the intent
  gate, breach evidence as the opening message. Nothing advances until the operator
  approves — the monitor acts with no human in the invocation path, yet never unsupervised.
  """
  def flag(attrs, evidence) do
    with {:ok, thread} <- open(Map.put(attrs, :born, "machine")) do
      post_brief(thread, evidence)
      {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
      Funes.Bus.broadcast({:workline_gated, parked})
      post_brief(parked, Brief.gate_message(parked))
      {:ok, parked}
    end
  end

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

    # Restaff BEFORE broadcasting: subscribers acting on the advance must never observe the
    # builder still leading a review stage.
    flipped = if flipped.stage == "review", do: restaff_reviewer(flipped), else: flipped
    Funes.Bus.broadcast({:workline_advanced, flipped})
    post_brief(flipped, Brief.stage_message(flipped))
    {:ok, flipped}
  end

  # Entering review: the world's reviewer takes the lead — the builder never approves its own
  # work by proxy. Best-effort (the stage already flipped and broadcast; a restaff fault must
  # not fail the advance) — but a MISS is posted, never silent: the operator sees that the
  # builder still holds a review it shouldn't.
  defp restaff_reviewer(%Thread{world_id: nil} = thread), do: restaff_miss(thread, "no world bound")

  defp restaff_reviewer(thread) do
    with %{roster: roster} when is_list(roster) <- Repo.get(Funes.World, thread.world_id),
         %{"name" => name} <- Enum.find(roster, &(&1["archetype"] == "reviewer" || &1[:archetype] == "reviewer")),
         {:ok, restaffed} <- Funes.Channel.assign_lead(thread.id, "#{name}-machine") do
      post_brief(restaffed, "→ #{name}-machine leads (review stage)")
      restaffed
    else
      {:error, reason} -> restaff_miss(thread, inspect(reason))
      _ -> restaff_miss(thread, "no reviewer in the world's roster")
    end
  rescue
    e -> restaff_miss(thread, Exception.message(e))
  end

  defp restaff_miss(thread, why) do
    post_brief(thread, "⚠ review stage could not restaff a reviewer (#{why}) — the current lead still holds it")
    thread
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
