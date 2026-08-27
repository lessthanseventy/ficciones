# Worklines slice 0: the eval harness — implementation plan

Design: `2026-08-27-ai-native-sdlc-workline-design.md` § "Evals on the steering config". This
slice regression-protects the coordination layer (triage routing, briefs, personas) before any
workline machinery lands. Boundary reality check: routing lives in ALEPH (`Aleph.MachineChat.
Staffing`/`Triage`/`Mention`) and funes has `deps: []` — so the harness CORE lives in funes
(boundary-exported), scenarios live per-module, and each module gets its own thin mix task.

## Shape

- `Funes.Eval.Scenario` — struct: `name`, `family`, `mode` (`:assert` | `:judge`), `run`
  (thunk → output), `expect` (assert mode: output → boolean), `judge_prompt` (judge mode:
  output → prompt string).
- `Funes.Eval` — runner: takes scenarios + opts (`judge:`, `mode: :all | :deterministic`),
  returns a report `%{results, passed, failed, skipped, judged_avg}`; renders a scorecard.
  Deterministic failures are hard failures; judged scenarios score 1–5 with rationale, pass
  bar = average ≥ 3.5. `:deterministic` mode skips judged scenarios entirely (offline gate).
- `Funes.Eval.Judge` — behaviour: `score(prompt) :: {:ok, %{scores: %{atom => 1..5},
  rationale: binary}} | {:error, term}`.
- `Funes.Eval.Judge.Claude` — headless `claude -p` on the cheap alias (`--model haiku`),
  strict-JSON reply parsed from stdout. Judge unavailable → `{:error, …}` → the full run
  fails loudly (never silently skips what it claimed to judge).
- Scenario corpora: `modules/funes/evals/*.exs` (brief/catch-up family — seeds an EPHEMERAL
  eval db, never the live/scratch one) and `modules/aleph/evals/*.exs` (routing family —
  pure, no db).
- Tasks: `mix funes.eval [--deterministic]` (forces `FUNES_DB=.dev/funes_eval.db`, fresh +
  migrated per run), `mix aleph.eval [--deterministic]` (no app boot — routing is pure).
- Gate wiring: deterministic eval joins `funes:check`/`aleph:check` (offline, fast); judged
  mode is `mise run funes:eval` / `aleph:eval`, run when steering files change. Deferred
  families (stage discipline, fence compliance) arrive with slices 2/3.

## Tasks

1. `Funes.Eval` core + `Scenario` + scorecard — TDD against inline scenarios.
2. `Judge` behaviour + `Judge.Claude` adapter (stub-tested; live call is the human smoke).
3. Corpus v1 (~15): routing (deterministic: mention wins, triage intents, builder default,
   surveyor never leads, empty roster nil, route_reason all three) + catch-up (deterministic:
   brief contains banked fact / todo / blocker; judged ×2: brief answerability, floor
   pinning rationale).
4. Mix tasks + mise `funes:eval`/`aleph:eval` + precommit wiring; gates; commit.

## Verification

Module suites green; `mise run funes:eval -- --deterministic` and `aleph` twin exit 0;
full judged run is the human's live smoke (needs `claude` auth). `mise run check` +
`flake:check` before calling the slice done.
