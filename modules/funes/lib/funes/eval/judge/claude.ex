defmodule Funes.Eval.Judge.Claude do
  @moduledoc """
  LLM-as-judge over a headless CLI. The command and model are CONFIGURATION, not design
  (funes AGENTS.md): `config :funes, eval_judge_cmd: ..., eval_judge_model: ...` — defaults
  to Claude Code's `claude -p` on the cheap alias (the plan bucket judges; fan-out stays off
  the expensive tier per the subagent routing rule). The scenario's prompt states the
  dimensions; this adapter only adds the strict-JSON reply contract and parses it.
  """

  @behaviour Funes.Eval.Judge

  @contract """
  You are a strict evaluator. Score the material below on the dimensions it names, each an
  integer 1 (worst) to 5 (best). Respond with ONLY a JSON object, no prose around it:
  {"scores": {"<dimension>": <1-5>, ...}, "rationale": "<one sentence>"}
  """

  @impl true
  def score(prompt) do
    case System.cmd(cmd(), ["-p", @contract <> "\n" <> prompt, "--model", model()], stderr_to_stdout: true) do
      {out, 0} -> parse(out)
      {out, code} -> {:error, {:judge_exit, code, String.slice(out, 0, 200)}}
    end
  rescue
    e in ErlangError -> {:error, {:judge_missing, Exception.message(e)}}
  end

  # The reply is ONLY-JSON by contract, but models decorate — try the whole trimmed output,
  # then every first-brace..closing-brace candidate from the END inward (a trailing footnote
  # with braces must not corrupt the real object). Score keys stay STRINGS: the runner only
  # reads values, and atomizing model-authored keys would mint unbounded atoms.
  @doc false
  def parse(out) do
    out
    |> candidates()
    |> Enum.find_value({:error, {:unparseable_judgement, String.slice(out, 0, 200)}}, fn blob ->
      case Jason.decode(blob) do
        {:ok, %{"scores" => scores, "rationale" => rationale}} when map_size(scores) > 0 ->
          {:ok, %{scores: scores, rationale: rationale}}

        _ ->
          nil
      end
    end)
  end

  defp candidates(out) do
    trimmed = String.trim(out)

    case :binary.match(trimmed, "{") do
      :nomatch ->
        []

      {start, _} ->
        tail = binary_part(trimmed, start, byte_size(trimmed) - start)
        closers = for {i, _} <- :binary.matches(tail, "}"), do: binary_part(tail, 0, i + 1)
        [trimmed | Enum.reverse(closers)]
    end
  end

  defp cmd, do: Application.get_env(:funes, :eval_judge_cmd, "claude")
  defp model, do: Application.get_env(:funes, :eval_judge_model, "haiku")
end
