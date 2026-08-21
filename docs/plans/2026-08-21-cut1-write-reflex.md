# Cut 1: Write Loop — the ledger is the reflexive default — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Durable machine-knowledge lands in funes automatically for every agent, and every fact carries the **intent** (what it was for) that Cut 3's value gradient will later grade against.

**Architecture:** Three surfaces. (1) funes gains an `intent` field on the fact write path. (2) pi's existing auto-capture (`manos/pi/src/capture.ts`, which *already* banks `derived` facts on a cadence) is extended to extract and pass intent. (3) claude-machine — which today has **no** auto-capture, the hole proven on 2026-08-21 when it hand-banked to its private Claude memory — gets a Claude Code Stop-hook capture reflex mirroring pi's, seeded into `.claude/settings.json`.

**Tech Stack:** Elixir/Ecto (funes, SQLite via `Funes.Repo`), Anubis MCP components, TypeScript (manos/pi extension, bun), Claude Code hooks, `scripts/funes-cli.sh` (bearer + MCP shell client). Run all mix via `mise exec -- mix`.

**Design reference:** `docs/plans/2026-08-21-one-ledger-write-read-value-design.md` (Cut 1).

**Discovery already done (do not re-litigate):**
- Fact schema: `modules/funes/lib/funes/fact.ex` — `bank_changeset/1` casts an explicit field list; no `intent` yet.
- Bank path: `Funes.MCP.Tool.BankFact` (`modules/funes/lib/funes/mcp/tool.ex:91`) → `Funes.Dossier.bank_fact/1` (`dossier.ex:45`) / `bank_stated_fact/2` (`dossier.ex:60`).
- pi capture pure core: `modules/manos/pi/src/capture.ts` (`CapturedFact`, `buildExtractionPrompt`, `parseExtraction`); banked in `extension.ts:138` via `client.bankFact(f.text, f.kind)`.
- claude-machine (`hronir` window) launches real `claude` via `Aleph.Cockpit.spawn_claude_window/0`; its Claude Code settings are the repo-root `.claude/settings.json` (has `sandbox`/`permissions`, **no `hooks` yet**).

---

## Task 1: funes — `intent` column on the fact table

**Files:**
- Create: `modules/funes/priv/repo/migrations/<ts>_add_intent_to_fact.exs`
- Modify: `modules/funes/lib/funes/fact.ex` (schema field list + `bank_changeset/1` cast list)
- Test: `modules/funes/test/funes/fact_test.exs` (confirm exact path first; else the changeset is unit-tested wherever `bank_changeset` is)

**Step 1: Write the failing test**

In the fact changeset test file, add:

```elixir
test "bank_changeset casts intent (what the fact was for)" do
  cs = Funes.Fact.bank_changeset(%{kind: "learned", text: "x", provenance: "derived", intent: "why we kept it"})
  assert cs.valid?
  assert Ecto.Changeset.get_change(cs, :intent) == "why we kept it"
end
```

**Step 2: Run it, verify it fails**

Run: `cd modules/funes && mise exec -- mix test test/funes/fact_test.exs -v`
Expected: FAIL — `intent` not cast (get_change returns nil).

**Step 3: Generate + write the migration**

Run: `cd modules/funes && mise exec -- mix ecto.gen.migration add_intent_to_fact`

Fill it:

```elixir
defmodule Funes.Repo.Migrations.AddIntentToFact do
  use Ecto.Migration

  def change do
    alter table(:fact) do
      add :intent, :text
    end
  end
end
```

**Step 4: Add the schema field + cast**

`fact.ex` schema block — add beside `:check_cmd`:

```elixir
    field :intent, :string
```

`fact.ex` `bank_changeset/1` — add `:intent` to the `cast/3` field list (leave `validate_required` unchanged — intent is optional).

**Step 5: Migrate + run the test**

Run: `cd modules/funes && mise exec -- mix ecto.migrate && mise exec -- mix test test/funes/fact_test.exs -v`
Expected: PASS.

**Step 6: Commit**

```bash
git add modules/funes/priv/repo/migrations modules/funes/lib/funes/fact.ex modules/funes/test/funes/fact_test.exs
git commit -m "funes: intent column on the fact write path (one-ledger Cut 1)"
```

---

## Task 2: funes — thread `intent` through Dossier + the bank_fact tool

**Files:**
- Modify: `modules/funes/lib/funes/dossier.ex` (`bank_fact/1`, `bank_stated_fact/2` — pass intent through if they whitelist keys)
- Modify: `modules/funes/lib/funes/mcp/tool.ex` (`Funes.MCP.Tool.BankFact` schema + `bank_derived`/`bank_stated`)
- Test: `modules/funes/test/funes/mcp/server_test.exs`

**Step 1: Write the failing MCP test**

In `server_test.exs`, add a test that calls `bank_fact` with `intent` and asserts the stored fact carries it (read back via `get_facts` or the repo). Model it on the existing `bank_fact` tests in that file.

```elixir
test "bank_fact stores intent (what the fact was for)", %{token: token, thread: thread} do
  session = handshake(token)
  call(token, session, 3, "register", %{})
  r = call(token, session, 4, "bank_fact", %{"kind" => "learned", "text" => "x", "intent" => "for the value loop"})
  refute r["isError"]
  fact = Funes.Repo.get_by!(Funes.Fact, thread_id: thread.id, text: "x")
  assert fact.intent == "for the value loop"
end
```

**Step 2: Run it, verify it fails**

Run: `cd modules/funes && mise exec -- mix test test/funes/mcp/server_test.exs -v`
Expected: FAIL — `fact.intent` is nil (tool drops it).

**Step 3: Add the tool schema field**

In `Funes.MCP.Tool.BankFact`'s `schema do` block:

```elixir
    field :intent, :string, description: "What this fact is FOR — the purpose the value loop later grades against"
```

**Step 4: Pass it through**

In `bank_derived/2`, add to the attrs map: `intent: Map.get(params, :intent),`. In `bank_stated/3`, add `intent: Map.get(params, :intent)` to the `bank_stated_fact` attrs. Confirm `Dossier.bank_fact/1` and `bank_stated_fact/2` forward the key to `Fact.bank_changeset/1` (they build the attrs map handed to the changeset — add `:intent` to any explicit key whitelist there).

**Step 5: Run the test**

Run: `cd modules/funes && mise exec -- mix test test/funes/mcp/server_test.exs -v`
Expected: PASS.

**Step 6: Update the tool moduledoc + commit**

Add one line to `BankFact`'s `@moduledoc` naming `intent`. Then:

```bash
git add modules/funes/lib/funes/dossier.ex modules/funes/lib/funes/mcp/tool.ex modules/funes/test/funes/mcp/server_test.exs
git commit -m "funes: bank_fact accepts intent, threaded to the fact row"
```

---

## Task 3: pi — capture extracts and banks `intent`

**Files:**
- Modify: `modules/manos/pi/src/capture.ts` (`CapturedFact`, `buildExtractionPrompt`, `parseExtraction`)
- Modify: `modules/manos/pi/src/extension.ts:138` (the `client.bankFact` call) + the funes MCP client's `bankFact` signature
- Test: the capture unit test (find it: `modules/manos/pi/**/capture*.test.ts` or `*.spec.ts`)

**Step 1: Write the failing parse test**

Add to the capture test file:

```ts
test("parseExtraction pulls intent per fact", () => {
  const out = parseExtraction('{"facts":[{"text":"x","kind":"learned","intent":"why"}],"questions":[]}');
  expect(out.facts[0].intent).toBe("why");
});
```

**Step 2: Run it, verify it fails**

Run: `cd modules/manos/pi && bun test src/capture` (confirm the runner; else `bun test`)
Expected: FAIL — `intent` undefined on the parsed fact.

**Step 3: Implement**

- `CapturedFact` interface: add `intent?: string;`
- `buildExtractionPrompt`: change the shape line to `{"facts":[{"text":"...","kind":"learned","intent":"..."}],"questions":[...]}` and add one sentence: `"intent is a short phrase for WHY this fact is worth keeping (what future work it serves)."`
- `parseExtraction`: in the facts loop, read `const intent = typeof (f as {intent?: unknown})?.intent === "string" ? (f as {intent: string}).intent.trim() : undefined;` and push `{ text, kind, intent }`.

**Step 4: Run the test**

Run: `cd modules/manos/pi && bun test src/capture`
Expected: PASS.

**Step 5: Wire the bank call**

`extension.ts:138`: `await client.bankFact(f.text, f.kind, f.intent)`. Extend the client's `bankFact` to send `intent` in the MCP tool args (optional param). Keep it backward-compatible (undefined → omitted).

**Step 6: Build + commit**

Run: `cd modules/manos/pi && bun run build` (or the repo's TS build/check task) — expect clean.

```bash
git add modules/manos/pi/src/capture.ts modules/manos/pi/src/extension.ts modules/manos/pi/**/capture*.test.ts
git commit -m "manos/pi: capture extracts + banks fact intent"
```

---

## Task 4: claude-machine — the missing capture reflex (Stop hook)

**This is the load-bearing task** — the hole proven on 2026-08-21. claude-machine has no auto-capture; give it pi's reflex in the Claude Code harness. Larger than Tasks 1–3; start with a spike.

**Files:**
- Create: `scripts/funes-capture.sh` (or `.ts` run via bun) — the hook body: read the turn transcript delta, extract durable facts, bank them `derived` via `scripts/funes-cli.sh`.
- Modify: `.claude/settings.json` (add a `hooks.Stop` entry invoking the script)
- Modify (later): `modules/aleph/lib/aleph/cockpit.ex` `spawn_claude_window/0` — so aleph *seeds* the hook into the hronir Claude's settings (one policy, per design). Defer to a follow-up if the spike shows the root `.claude/settings.json` is already what hronir loads.

**Step 0 (SPIKE — do first, timebox):**
1. Confirm the Stop-hook transcript surface: what Claude Code passes a Stop hook (transcript path / stdin JSON). Run a throwaway Stop hook that dumps its input to a file; inspect it.
2. Confirm `scripts/funes-cli.sh` can bank a fact non-interactively (it already mints the bearer for the MCP `Authorization` header — check for a `bank_fact` verb or add one that POSTs the `tools/call`).
3. Decide the extractor: reuse pi's pure core (`capture.ts` `buildExtractionPrompt`/`parseExtraction`) by invoking it from bun in the hook, calling the same cheap ollama model — **DRY: do not re-implement the prompt/parse.**

If the spike reveals the extractor can't be cleanly shared across harnesses, STOP and open a focused brainstorm — do not fork a second extraction prompt.

**Step 1: Write the failing test (extractor reuse)**

Add a bun test asserting the shared extractor path used by the hook returns facts from a sample delta (reusing `parseExtraction`). This pins the DRY reuse, not the LLM call.

**Step 2–4: Implement the hook script**

`scripts/funes-capture.sh` (or `.ts`): read delta since a per-session watermark → `redactSecrets` → `buildExtractionPrompt` → cheap completion → `parseExtraction` → for each fact `funes-cli.sh` bank_fact with `text`, `kind`, `intent`. Mirror `extension.ts`'s cadence/failure-is-a-noop discipline. Watermark stored under the scratch/state dir.

**Step 5: Register the Stop hook**

Add to `.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [ { "type": "command", "command": "bash scripts/funes-capture.sh" } ] }
  ]
}
```

**Step 6: Live-verify (the real gate — @verify)**

Run a real claude-machine turn that learns something durable; confirm the fact lands in funes (`search_facts`) with an `intent`, **without any hand-banking**. This is the success test for Cut 1. Use the `verify` skill.

**Step 7: Commit**

```bash
git add scripts/funes-capture.sh .claude/settings.json
git commit -m "claude-machine: Stop-hook capture reflex banks durable facts to funes"
```

---

## Definition of done (Cut 1)

- A fact banked by any agent can carry `intent`; the pi and claude-machine reflexes both bank `derived` facts unbidden.
- Success test: run a task, hand-bank nothing; afterward the machine-knowledge is all in funes, discoverable by another agent, each fact carrying what it was for.
- Full gates green: `cd modules/funes && mise exec -- mix test`; `cd modules/aleph && mise run aleph:check`; the pi TS build/test. (Unit suites are not the gate — run the module `:check`.)
