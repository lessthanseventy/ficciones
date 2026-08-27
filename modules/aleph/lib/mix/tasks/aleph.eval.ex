defmodule Mix.Tasks.Aleph.Eval do
  @shortdoc "Run aleph's steering evals (routing) — --deterministic for the offline gate set"
  @moduledoc """
  #{@shortdoc}.

  Loads every scenario in `evals/` and runs it through `Funes.Eval`. The routing family is
  pure (staffing/triage/mention over a fixture cast), so no app boot and no db — just the
  compiled modules. `--deterministic` skips judged scenarios (none yet in this corpus); the
  precommit gate runs that mode. Exits nonzero on any failure.
  """
  use Mix.Task
  use Boundary, classify_to: Aleph

  @impl Mix.Task
  def run(argv) do
    mode = if "--deterministic" in argv, do: :deterministic, else: :all
    Mix.Task.run("compile")

    report = "evals" |> Funes.Eval.load() |> Funes.Eval.run(mode: mode)
    Mix.shell().info(Funes.Eval.scorecard(report))
    if !report.ok?, do: Mix.raise("aleph.eval failed")
  end
end
