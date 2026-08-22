# Coworker Archetypes (Layer 1) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn `Aleph.Profiles` into an **archetype taxonomy** — role templates (reviewer/planner/builder/surveyor/researcher/assistant), each a distilled discipline — plus a `{archetype, name, model, knobs}` roster-entry shape and an `instantiate/1` that produces a named coworker from an archetype. The shared foundation both worlds (Slice 1) and the crew engine consume.

**Architecture:** Keep the existing `%Aleph.Profile{}` struct as the *materialisation-ready* shape (nothing downstream changes). Add an `archetype` field + an archetype registry keyed by archetype atom. A **roster entry** references an archetype by key and supplies an instance `name` (the funes handle), an optional `model` override, and `knobs`. `Profiles.instantiate(entry)` returns a `%Profile{}` whose *identity* (name → socket/config_dir/handle) is the instance name and whose *content* (mcp/sandbox/permissions/system_prompt/default model) comes from the archetype. Existing name-keyed `fetch/1` stays working (Slice 0's live tertius spawn is untouched). **Out of scope:** the cockpit single→N-coworker spawn rewire and the `@base_coworkers`/`@machine_agent` de-singletoning — that's Slice 1, when worlds spawn rosters.

**Tech Stack:** Elixir, `modules/aleph`, `Aleph.Profiles` (`lib/aleph/profiles.ex`), `Aleph.Config` (runtime overrides), ExUnit. No funes or cockpit changes in this layer.

---

## Assumptions

- **A1 — `%Profile{}` stays the materialisation contract.** `render/3`/`materialise!/2`/`socket/1`/`config_dir/1` keep keying off `profile.name`. `instantiate/1` just *produces* a `%Profile{}` with the instance name; the whole downstream pipeline is unchanged. This is why layer 1 needs no cockpit edits.
- **A2 — `tertius` and `reviewer` are re-expressed as archetype instances, not deleted.** `tertius` = the `:surveyor` archetype instanced under name `"tertius"`; the current `reviewer` profile = the `:reviewer` archetype. `fetch("tertius")` must return a byte-identical materialisation to today (regression-guarded), so the live Tlön spawn can't break.
- **A3 — Per-coworker model override precedence:** roster-entry `model` > `Aleph.Config.coworker_model(name)` (SETTINGS panel) > archetype default. Documented + tested.
- **A4 — Archetype keys are atoms** (`:reviewer`, `:planner`, `:builder`, `:surveyor`, `:researcher`, `:assistant`); instance names are strings (funes handles).

---

## Task 1: Add the `archetype` field + tag the two existing profiles

**Files:**
- Modify: `modules/aleph/lib/aleph/profiles.ex` (defstruct ~L25, typespec ~L34, the `tertius`/`reviewer` entries ~L377-396)
- Test: `modules/aleph/test/aleph/profiles_test.exs`

**Step 1 — Failing test:**
```elixir
test "every registered profile declares an archetype atom" do
  for p <- Aleph.Profiles.all() do
    assert is_atom(p.archetype) and not is_nil(p.archetype)
  end
end

test "tertius is the surveyor archetype, reviewer is the reviewer archetype" do
  assert Aleph.Profiles.fetch("tertius").archetype == :surveyor
  assert Aleph.Profiles.fetch("reviewer").archetype == :reviewer
end
```
(If no `all/0` exists, add `def all, do: @profiles`.)

**Step 2 — Verify fail** (`archetype` field undefined).

**Step 3 — Implement:** add `archetype: nil` to `defstruct` + `archetype: atom()` to the typespec; set `archetype: :surveyor` on tertius, `archetype: :reviewer` on the reviewer profile.

**Step 4 — Verify pass; `mise run aleph:check`.**

**Step 5 — Commit:** `aleph: add archetype field to Aleph.Profile`

---

## Task 2: The archetype registry + seed the four new templates

Introduce archetype *templates* (the role, minus a name) and seed planner/builder/researcher/assistant beside the existing surveyor(tertius)/reviewer content.

**Files:**
- Modify: `modules/aleph/lib/aleph/profiles.ex` — add `@archetypes` (a map `archetype_atom => template`), the four new role prompts (`@planner_role`, `@builder_role`, `@researcher_role`, `@assistant_role`), and per-archetype defaults (model, mcp, sandbox, permissions). Reuse existing constants: builder → `@tlon_sandbox`/`@tlon_permissions`/`@tlon_funes_mcp`; reviewer → `@reviewer_permissions`; researcher/assistant → sandbox scoped to the world's paths (start from `@tlon_sandbox`, note as tunable).
- Test: `modules/aleph/test/aleph/profiles_test.exs`

**Step 1 — Failing test:**
```elixir
test "the seed archetype set is present with sane defaults" do
  keys = Aleph.Profiles.archetypes() |> Map.keys() |> Enum.sort()
  assert keys == ~w(assistant builder planner researcher reviewer surveyor)a
end

test "reviewer archetype cannot write (deny floor), builder can" do
  assert get_in(Aleph.Profiles.archetype(:reviewer).permissions, ["permission", "write"]) == "deny"
  assert get_in(Aleph.Profiles.archetype(:builder).permissions, ["permission", "write"]) != "deny"
end

test "each archetype has a non-empty system prompt and a default model" do
  for {_k, t} <- Aleph.Profiles.archetypes() do
    assert is_binary(t.system_prompt) and t.system_prompt != ""
    assert match?(%{model: _}, t) and not is_nil(t.model)
  end
end
```

**Step 2 — Verify fail** (`archetypes/0`, `archetype/1` undefined).

**Step 3 — Implement:** define `@archetypes`; add `def archetypes, do: @archetypes` and `def archetype(k), do: Map.fetch!(@archetypes, k)`. Each template is a map `%{model:, mcp:, sandbox:, permissions:, system_prompt:, add_extensions:}` — the `%Profile{}` fields minus `name`. Model defaults per the design table (reviewer/planner/builder/researcher/assistant → sonnet via the anthropic provider tuple; surveyor → glm-5.2). The four new role prompts: distilled, terse system prompts (reviewer = the code-review protocol from `@reviewer_role`; planner = writing-plans discipline; builder = TDD/RED-GREEN-REFACTOR + verification-before-completion; researcher = deep-research multi-source+verify; assistant = general life-assistant). Keep prompts real but concise — they are the extracted disciplines.

**Step 4 — Verify pass; `mise run aleph:check`.**

**Step 5 — Commit:** `aleph: seed the coworker archetype registry (reviewer/planner/builder/surveyor/researcher/assistant)`

---

## Task 3: `instantiate/1` — a named coworker from a roster entry

**Files:**
- Modify: `modules/aleph/lib/aleph/profiles.ex` — add `instantiate/1`
- Test: `modules/aleph/test/aleph/profiles_test.exs`

**Step 1 — Failing test:**
```elixir
test "instantiate builds a named Profile from an archetype, content from the template" do
  p = Aleph.Profiles.instantiate(%{archetype: :builder, name: "atlas"})
  assert p.name == "atlas"                       # identity = the instance name
  assert p.archetype == :builder
  assert p.system_prompt == Aleph.Profiles.archetype(:builder).system_prompt
  assert Aleph.Profiles.socket(p.name) == "aleph-atlas"   # socket keys off instance name
end

test "roster-entry model overrides the archetype default" do
  entry = %{archetype: :reviewer, name: "vera", model: %{provider: "anthropic", model: "sonnet", thinking: "low"}}
  assert Aleph.Profiles.instantiate(entry).model.model == "sonnet"
end

test "two instances of one archetype get distinct identities" do
  a = Aleph.Profiles.instantiate(%{archetype: :builder, name: "atlas"})
  b = Aleph.Profiles.instantiate(%{archetype: :builder, name: "borges"})
  assert a.name != b.name and a.archetype == b.archetype
end
```

**Step 2 — Verify fail** (`instantiate/1` undefined).

**Step 3 — Implement:**
```elixir
@doc "Build a materialisation-ready %Profile{} from a roster entry: identity from `name`, content from the archetype, model overridable."
def instantiate(%{archetype: key, name: name} = entry) do
  t = archetype(key)
  %Profile{
    name: name,
    archetype: key,
    add_extensions: Map.get(t, :add_extensions, []),
    mcp: t.mcp,
    model: entry[:model] || Aleph.Config.coworker_model(name) || t.model,   # A3 precedence
    sandbox: t.sandbox,
    permissions: apply_yolo_override(t.permissions, Aleph.Config.coworker_yolo(name)),
    system_prompt: t.system_prompt
  }
end
```
(Extract the yolo-merge helper if it's currently inlined in `fetch/1`.)

**Step 4 — Verify pass; `mise run aleph:check`.**

**Step 5 — Commit:** `aleph: Profiles.instantiate/1 — named coworker from an archetype roster entry`

---

## Task 4: Route `fetch/1` through the archetype path (back-compat, no cockpit change)

Make the existing name-keyed `fetch/1` resolve via archetypes so there's ONE content source, while keeping its output byte-identical for `"tertius"`/`"reviewer"` (the live spawn path must not change).

**Files:**
- Modify: `modules/aleph/lib/aleph/profiles.ex` — a seed name→entry table (`"tertius" => %{archetype: :surveyor, name: "tertius", model: <glm-5.2>}`, `"reviewer" => %{archetype: :reviewer, name: "reviewer"}`); `fetch/1` resolves the entry then `instantiate/1`, preserving the runtime overrides it applies today.
- Test: `modules/aleph/test/aleph/profiles_test.exs`

**Step 1 — Failing/guard test (regression — the important one):**
```elixir
test "fetch('tertius') materialises identically before and after the archetype refactor" do
  # Pin the rendered output so the live Tlön spawn is provably unchanged.
  r = Aleph.Profiles.render(Aleph.Profiles.fetch("tertius"), %{}, %{})
  assert r.system_prompt == @tertius_role
  assert r.settings["defaultModel"] == "glm-5.2"
  assert r.mcp["mcpServers"]["funes"]["directTools"] |> Enum.member?("machine_overview")
end
```
(Adapt the exact `render/3` arity/return keys to the real signature from the code.)

**Step 2 — Verify fail/behaviour-lock:** run BEFORE refactor to capture the golden values, then refactor and keep it green.

**Step 3 — Implement:** `fetch(name)` → look up the seed entry (or fall back to a bare `%{archetype: <by-name>, name: name}`), `instantiate/1`, then the same `apply_model_override`/`apply_yolo_override` it does today (now largely inside `instantiate`). Ensure `tertius`'s glm-5.2 + `machine_overview` MCP survive.

**Step 4 — Verify pass; `mise run aleph:check`; then a `grep` that no caller of `fetch/1` broke.**

**Step 5 — Commit:** `aleph: fetch/1 resolves through the archetype registry (tertius/reviewer unchanged)`

---

## Definition of done

- `mise run aleph:check` green (format + warnings-as-errors + suite).
- Six archetypes registered with distinct disciplines; reviewer carries a write-deny floor, builder does not.
- `instantiate/1` produces a named `%Profile{}` from `{archetype, name, model, knobs}`; two instances of one archetype get distinct identities (name → socket/config_dir); model precedence is entry > Config > archetype.
- **Regression:** `fetch("tertius")` materialises byte-identically to pre-refactor (the live Slice-0 Tlön spawn is provably untouched) — no cockpit/mention edits in this layer.
- The `{archetype, name, model, knobs}` roster shape is the exact contract Slice 1's `world.roster[]` will store and spawn.

## Deferred (Slice 1, not here)

- De-singletoning the cockpit spawn: `@machine_agent`/`@machine_window`/`@tlon_session`, the three `ensure_*_coworker` spawners, and `@base_coworkers` (fixed 2-entry) → a loop over a world's roster keyed by instance name.
- `knobs` semantics (currently carried, not yet consumed).
- Per-archetype sandbox scoping to a world's paths (researcher/assistant start from `@tlon_sandbox`).
- Importing external agent templates (agency-agents/VoltAgent) into `@archetypes`.
