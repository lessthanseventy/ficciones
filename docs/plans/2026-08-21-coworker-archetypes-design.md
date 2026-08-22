# Coworker Archetypes + Worlds Slice 1 — Design

> Validated design (brainstorm, operator + claude-machine, 2026-08-21). Foundation for the
> worlds/orbis reshape Slice 1 (`docs/plans/2026-08-21-worlds-orbis-reshape-design.md`) and the
> funes-native coordination strand (`docs/plans/2026-08-21-funes-native-review-coworkers-design.md`).
> Slice 0 (the collapse) is merged; this is what comes next.

## The three-layer model (the load-bearing frame)

The reshape's "roster" isn't arbitrary names — it decomposes into three layers with **different homes**,
so each ships independently:

| Layer | What | Home |
|---|---|---|
| **1. Archetypes** | the roles — each a discipline made flesh (reviewer/planner/builder/surveyor/…) | **nix capabilities** (profile templates, like today's `tertius`) |
| **2. Composition** | a world picks a *roster* of archetypes + paths + knobs | **funes** `world` entity (Slice 1) |
| **3. Coordination** | the "workflow engine" — leader composes a per-task crew, sequences builder→reviewer, gates on review, funes threads capture the hand-offs | the **crew plugin** (separate strand; design 2026-08-20) |

**Sequencing (decided):** archetypes **first** (both other layers need them), then layer 2 (Slice 1)
and layer 3 (crew) ship in parallel over the shared taxonomy. This is where "capture superpowers as
coworkers" actually lands: an archetype's system prompt *is* the extracted superpowers discipline.

---

## Layer 1 — the archetype taxonomy

**Principle: small-but-extensible.** The public ecosystem proves the space is unbounded and dev-skewed
(agency-agents ~400 agents/19 divisions; VoltAgent ~154; wshobson ~194). We seed a tight set covering
our *actual* world types and make adding more a matter of dropping in a template. Their format
(md + frontmatter: `name`, `model`, `description`, `tools`, prompt) maps ~1:1 onto `Aleph.Profiles`,
so **import-on-demand** from those repos is cheap — a later convenience, not seeded.

**An archetype** is a nix-owned profile template (generalizing `Aleph.Profiles.tertius`):
system prompt (the distilled discipline) · default model · permissions · sandbox · MCP tools.

**Seed set:**

| Archetype | Discipline / source | Default model | Permissions |
|---|---|---|---|
| **reviewer** | code-review protocol — adversarial diff review, Critical/Important/Minor, verify-against-real-code | sonnet | read + post findings (`raise_issue`), **no write** |
| **planner** | writing-plans — bite-sized TDD tasks, exact paths, DoD | sonnet | read + write plan docs |
| **builder** | TDD + verification-before-completion — RED→GREEN→REFACTOR | sonnet | full dev in the world's paths (sandbox/allowlist) |
| **surveyor** | `tertius` (exists) — god-view / Orbis meta agent | glm-5.2 | read `machine_overview` |
| **researcher** | the `deep-research` skill — multi-source, adversarial verify, cited synthesis | sonnet | read + web |
| **assistant** | general life-assistant (the design's `personal-life` roster example) | sonnet | scoped to the world's paths |

`researcher`/`assistant` are seeded (not just dev) deliberately: the release-bar second world may be a
**life** world ("personal life on a Tuesday" — the design's own example), which forces the taxonomy to
be general on day one, not retrofitted. Model-routing follows the `subagent-model-routing` rule —
reviewers/builders on sonnet, the session/opus bucket reserved for the leader.

**A roster entry** (how a world references an archetype):

```
{ archetype: :reviewer,   # → the nix profile template (prompt, default model, perms, tools)
  name:      "vera",       # persona / display name = the funes @-mention handle
  model:     "sonnet",     # OPTIONAL per-coworker override (defaults from the archetype)
  knobs:     %{} }         # per-instance config
```

- **name** is first-class → a world can have two builders with distinct identities; it *is* the funes
  handle (@-mention routing via `Aleph.Mention`), replacing today's hardcoded `tertius-machine` etc.
- **model** is a configurable override knob, never baked into the prompt (mirrors how `Profiles.fetch`
  already merges runtime model overrides).
- **archetype** stays the reusable template.

---

## Layer 2 — Slice 1: worlds compose rosters

**The funes `world` entity** (first-class, seeded — NOT a fact, NOT a side-store; funes stays sole owner):

```
worlds:  id · name · type(code|life|blank) · paths[] · roster[<entry>] · knobs{} · scope(machine|project) · created_at
```

MCP tools: `register_world`, `list_worlds`, `edit_world`, `remove_world`. `roster[]` and each entry's
`archetype`/`model` reference capabilities **by name** — nix defines what a `reviewer` *is*; funes
records that this world *uses* one named "vera". Boundary law intact (the `:boundary` compiler still
holds; funes never reaches up to define capabilities).

**Seeding.** The flake seeds one row at bootstrap — the dogfood cast as **world #1 "Tlön"**
(`type: code`, `paths: [modules/*]`, `roster: [{surveyor, "tertius"}, …]`, `scope: machine`).
Thereafter funes owns it like any other world → *Tlön becomes editable*, and "no special-casing for THE
Tlön" falls out for free. New worlds start from a seeded default template (duplicate-and-tweak).

**aleph read path (replaces the two Slice 0 hardcodes).** `Space.all/0`'s Tlön struct and the literal
`"Tlön"` in `Orbis.worlds/1` both become reads of `list_worlds` (via a thin `Funes.Worlds` /
`Aleph.Worlds` seam). The picker stays **[Orbis, <active world>]**; Orbis' survey is the world-switcher —
`Enter` on a survey row sets the active world (extends Slice 0's `Enter → :switch_space`).

**Zoom-into-world generalizes the Tlön runtime.** Today the center is a hardcoded `tlon` tmux session +
`tertius` spawn (`spawn_machine_coworker`, `tlon_tmux` deriving its socket from `Space.fetch(:tlon)`).
Slice 1 keys these **by world**: entering world N attaches its own tmux session and **lazily spawns its
roster** on first zoom (exactly like Slice 0's `ensure_machine_coworker` spawns tertius on entering
Tlön). One panel-set for all worlds in Slice 1 — `type` is a stored knob but does **not** yet drive
per-type panels (that's "Later").

**Author face** = a **form over a seeded row** (absorbs the Settings modal): shows a world's fields
(type/paths/roster/knobs) as editable; "new world" = duplicate a template and tweak. Evolves the
existing Settings-modal pattern — least new UI.

**Release bar (Slice 1 done):** a **second world row appears in Orbis' survey**, spawned from the author
face, touching no aleph/funes code — and is enterable (its roster spawns lazily).

---

## Layer 3 — coordination (separate strand)

The "who does what when" workflow engine is **not** part of Slice 1. It's the crew plugin
(`docs/plans/2026-08-20-funes-crew-plugin-design.md` + `docs/plans/2026-08-21-funes-native-review-coworkers-design.md`):
a leader composes a per-task crew of archetypes, sequences builder→reviewer, gates on review, funes
threads capture the hand-offs — the native replacement for superpowers' `subagent-driven-development`.
It operates *within* a world, over that world's roster, and consumes the same layer-1 taxonomy.

---

## Sequencing & next artifacts

1. **Archetypes plan** (layer 1) — the seed profile templates + the `{archetype, name, model, knobs}`
   roster shape. Shared foundation; build first.
2. **Slice 1 plan** (layer 2) — funes `world` entity + tools + flake seeding + aleph read path + zoom-
   into-world + author face. Consumes layer 1.
3. **Crew plan** (layer 3) — separate strand, parallelizable once layer 1 exists.

## Deferred / open

- **Per-type panel-sets** (code lights Commits/Leaves/PTYs; life/blank drop the dead furniture) —
  "Later — world types & grouping" in the reshape doc. Slice 1 stores `type` but ships one panel-set.
- **Import from external agent repos** (agency-agents/VoltAgent → profile templates) — on-demand, not seeded.
- **Grouping worlds into orgs/folders** — YAGNI until the flat list is crowded (`scope` is the backbone).
- Exact author-face field-editing interactions (validation, roster add/remove UX) — settle in the Slice 1 plan.
