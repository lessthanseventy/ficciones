defmodule Funes.Eval.Judge.Claude do
  @moduledoc """
  LLM-as-judge over headless Claude Code (`claude -p`), pinned to the cheap alias — the
  session/plan bucket judges; fan-out stays off the expensive tier (see the subagent
  routing rule). The scenario's prompt states the dimensions; this adapter only adds the
  strict-JSON reply contract and parses it.
  """

  @behaviour Funes.Eval.Judge

  @model "haiku"

  @contract """
  You are a strict evaluator. Score the material below on the dimensions it names, each an
  integer 1 (worst) to 5 (best). Respond with ONLY a JSON object, no prose around it:
  {"scores": {"<dimension>": <1-5>, ...}, "rationale": "<one sentence>"}
  """

  @impl true
  def score(prompt) do
    case System.cmd("claude", ["-p", @contract <> "\n" <> prompt, "--model", @model], stderr_to_stdout: true) do
      {out, 0} -> parse(out)
      {out, code} -> {:error, {:claude_exit, code, String.slice(out, 0, 200)}}
    end
  rescue
    e in ErlangError -> {:error, {:claude_missing, Exception.message(e)}}
  end

  # The reply is ONLY-JSON by contract, but a model preamble happens — take the first {...} blob.
  @doc false
  def parse(out) do
    with [blob] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{"scores" => scores, "rationale" => rationale}} when map_size(scores) > 0 <- Jason.decode(blob) do
      {:ok, %{scores: Map.new(scores, fn {k, v} -> {String.to_atom(k), v} end), rationale: rationale}}
    else
      _ -> {:error, {:unparseable_judgement, String.slice(out, 0, 200)}}
    end
  end
end
