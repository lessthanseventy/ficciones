defmodule Funes.Workline.Brief do
  @moduledoc """
  The stage brief — the message that IS the wake (worklines slice 2). When a workline flips,
  funes posts the entered stage's brief on the thread; delivery rides the existing lead-wake
  path (a funes-authored message with no mention falls back to the staffed lead). Pure text
  here: playbook + read-list + owed exit artifact + the advance verb. Stage playbooks are
  the ADVISORY half of governance (skills, not hooks) — world knobs can override later.
  """

  alias Funes.Thread

  @doc "The brief for the stage the workline just ENTERED (merged → a completion note)."
  def stage_message(%Thread{stage: "merged"} = t) do
    "✅ workline #{t.slug} is merged — the chain is complete. History: work/#{t.slug}/ + this thread."
  end

  def stage_message(%Thread{} = t) do
    String.trim("""
    ▶ #{String.upcase(t.stage)} — workline #{t.slug}
    Read: #{read_list(t)}
    #{playbook(t)}
    Exit: commit #{owed(t)}, then call advance_stage.#{gate_note(t.stage)}
    """)
  end

  @doc "The parked-gate notice — what's waiting and the operator's completion verb."
  def gate_message(%Thread{} = t) do
    "⏸ workline #{t.slug} is parked at #{t.stage} — this transition is the operator's. " <>
      "Approve with: mise run funes:cli -- approve #{t.id} (funes-cli approve #{t.id})."
  end

  defp playbook(%{stage: "spec"}),
    do:
      "Interview the operator IN THIS THREAD until requirements and design fit one document; draft it — do not re-ask what the world's knobs and floor constraints already state."

  defp playbook(%{stage: "plan"}),
    do:
      "Break the spec into bite-sized, verifiable tasks with exact files — an engineer with zero context could execute them."

  defp playbook(%{stage: "build"} = t),
    do:
      "Implement on branch work/#{t.slug}, test-first; every commit stays green. The failing tests are read-only to you."

  defp playbook(%{stage: "verify"} = t),
    do:
      "Run the module gates AND the machine gate; record each result via record_check with correlation workline:#{t.slug}:verify — evidence, not self-report."

  defp playbook(%{stage: "review"}),
    do: "You are the reviewer, not the builder: findings against spec compliance, bugs, security — verdict at the top."

  defp playbook(%{stage: "intent"}), do: "Capture the originator's words near-verbatim plus a one-line restatement."

  # What to read on entry — artifacts first (git is the record), dossier for the live state.
  defp read_list(%{stage: "intent"} = t), do: "the operator's opening message on this thread#{dossier_tail(t)}"
  defp read_list(%{stage: "spec"} = t), do: "#{dir(t)}/intent.md#{dossier_tail(t)}"
  defp read_list(%{stage: "plan"} = t), do: "#{dir(t)}/intent.md · #{dir(t)}/spec.md#{dossier_tail(t)}"
  defp read_list(%{stage: "build"} = t), do: "#{dir(t)}/spec.md · #{dir(t)}/plan.md#{dossier_tail(t)}"
  defp read_list(%{stage: "verify"} = t), do: "#{dir(t)}/plan.md · the branch work/#{t.slug}#{dossier_tail(t)}"

  defp read_list(%{stage: "review"} = t),
    do: "#{dir(t)}/spec.md · #{dir(t)}/plan.md · the diff on branch work/#{t.slug}#{dossier_tail(t)}"

  defp dossier_tail(_t), do: " · get_dossier for live state"

  defp owed(%{stage: "intent"} = t), do: "#{dir(t)}/intent.md"
  defp owed(%{stage: "spec"} = t), do: "#{dir(t)}/spec.md"
  defp owed(%{stage: "plan"} = t), do: "#{dir(t)}/plan.md"
  defp owed(%{stage: "build"} = t), do: "commits on branch work/#{t.slug}"
  defp owed(%{stage: "verify"} = t), do: "passing CHECKS (workline:#{t.slug}:verify)"
  defp owed(%{stage: "review"} = t), do: "#{dir(t)}/review.md"

  defp gate_note(stage) when stage in ["spec", "review"], do: " This stage's exit gates on the operator."
  defp gate_note(_stage), do: ""

  defp dir(t), do: "work/#{t.slug}"
end
