# Elixir repo tools — how an agent reads, edits, runs and updates an Elixir repo (design)

Andrew, 2026-09-08: "there has to be a bunch more mix ast.thing tasks we can beef up the editing
capabilities with — introspection too — a whole interface for how agents work with and edit and
run and update inside an Elixir repo, Expert-aware and the whole deal." Prompted by a night of
text edits dying to `mix format` reflows and the first `mix ast.rename` (Sourceror patches)
landing clean.

## Principle

One library, three doors. Every verb is a pure function in `Server.Source.*` (edits) or
`Server.Repo.*`-style introspection modules, taking source or a path and returning data or a
patched string; the doors are a `mix` task (the operator, and Claude in a shell), an MCP verb
(a coworker), and the console (the drawer, later). Edits are PATCHES computed from AST ranges,
never a reprint: only the bytes the verb names move, comments and layout stay. Every edit
returns the diff it made and the compile result after it; a verb that cannot verify says so.

Three engines, each for what it is good at:

- **Sourceror** — parse with comments, ranges, patches. Edits and single-file introspection.
- **Expert (LSP)** — cross-file semantics: references, definitions, rename-with-references,
  diagnostics as the compiler sees them. Reached over stdio through the adapters' `lspd`.
- **Mix** — compile, test, format, deps, the gates (`mise run …` is the one API on top).

## The verbs

Edit (Sourceror; `mix ast.*` today, `edit_*` MCP verbs):

| verb | does |
|---|---|
| `rename OLD NEW [--atoms] [--comments] FILES` | LANDED — identifier everywhere; atoms/keys and whole-word comment mentions on request |
| `rename-refs OLD NEW` | rename via Expert's references (cross-file, module-qualified calls) |
| `delete-clause Mod.fun/arity HEAD` | remove one clause matching a head pattern |
| `insert-clause Mod.fun/arity after HEAD CODE` | add a clause at the right place in the group |
| `replace-body Mod.fun/arity HEAD CODE` | swap a clause's body |
| `add-alias Mod Alias` / `add-import` | at the top of the invoking module, once |
| `move-def Mod.fun/arity to Mod2` | a def and its clauses across modules (Expert fixes callers) |

Introspect (read-only; `mix ast.outline` etc., `inspect_*` MCP verbs):

| verb | returns |
|---|---|
| `outline FILE` | modules → defs with arity, spec, doc first line, line ranges |
| `refs Mod.fun/arity` | every call site (Expert) |
| `callers`/`callees` | the graph one hop out (Mix xref) |
| `exports` | the `:boundary` surface — what a consumer may call |
| `diagnostics [FILE]` | compiler + credo, as data |
| `deps` | what's outdated, what has an advisory (`mix hex.outdated`, `mix hex.audit`) |

Run and update (Mix behind mise; already tasks — exposed as verbs with structured output):
`check`, `test FILE[:LINE]`, `format FILES`, `deps.get`, `deps.update PKG`, `release`, `restart`.

## Shape

- `Server.Source.Rename` exists. Next modules: `Server.Source.Clause` (delete/insert/replace),
  `Server.Source.Outline`, `Server.Source.Refs` (Expert client), all `@spec`'d, all tested on
  source strings (no files) plus one file-level test per mix task.
- The MCP verbs ride the existing machine-scope tool surface (`Console.Profiles` cuts them per
  archetype: a reviewer gets introspection only; a builder gets edits; the gates run for everyone).
- Every edit verb: `{:ok, diff, compile: :ok | {:error, diagnostics}}` — the coworker sees what it
  did and whether it still builds, in one turn.
- The console's drawer gets an OUTLINE pane for the open thread's worktree files (later).

## Order

1. `ast.rename --comments`, `ast.outline`, `ast.diagnostics` (all single-engine, small).
2. Clause verbs (`Server.Source.Clause`).
3. Expert client (`refs`, `rename-refs`) — depends on the adapters' lspd being stable.
4. MCP exposure per archetype; the tlon-shaped `/implement` runs on these.

Ties to `2026-09-08-tlon-shaped-flows.md` (the implement skill's toolbox) and the value-loop plan
(review coworkers read `refs`/`diagnostics`, not raw diffs).
