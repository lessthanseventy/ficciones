# Elixir repo tools — how an agent reads, edits, runs and updates an Elixir repo (design)

Andrew, 2026-09-08: "there has to be a bunch more mix menard.thing tasks we can beef up the editing
capabilities with — introspection too — a whole interface for how agents work with and edit and
run and update inside an Elixir repo, Expert-aware and the whole deal." Prompted by a night of
text edits dying to `mix format` reflows and the first `mix menard.rename` (Sourceror patches)
landing clean.

## Principle

One library, three doors. Every verb is a pure function in `Menard.*` (edits — modules/menard, its own project so the tasks run while the app being edited does not compile) or
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

Edit (Sourceror; `mix menard.*` today, `edit_*` MCP verbs):

| verb | does | status |
|---|---|---|
| `menard.rename OLD NEW [--atoms] [--comments] FILES` | identifier everywhere; atoms/keys and whole-word comment mentions on request | LANDED · MCP `rename_identifier` |
| `menard.clause replace FILE name/arity HEAD CODE` | swap a clause's body | LANDED · MCP `edit_clause` |
| `menard.clause delete FILE name/arity HEAD` | remove one clause (+ its glued comment) | LANDED · MCP `edit_clause` |
| `menard.clause insert-after FILE name/arity HEAD CODE` | add a clause after that one | LANDED · MCP `edit_clause` |
| `rename-refs OLD NEW` | rename via Expert's references (cross-file, module-qualified calls) | needs the Expert client |
| `add-alias Mod Alias` / `add-import` | at the top of the invoking module, once | next |
| `move-def Mod.fun/arity to Mod2` | a def and its clauses across modules (Expert fixes callers) | needs the Expert client |

Introspect (read-only):

| verb | returns | status |
|---|---|---|
| `menard.outline FILE [--json]` | modules → defs with arity, spec, doc first line, line ranges | LANDED · MCP `outline_file` |
| `menard.diagnostics [--json]` | a forced compile's warnings as data | LANDED |
| `menard.inspect callers MOD[.fun/arity]` | files calling into it (mix xref) | LANDED |
| `menard.inspect exports` | the `:boundary` surface — what a consumer may call | LANDED |
| `menard.inspect deps` | outdated packages + advisories | LANDED |
| `menard.find calls TARGET \| defs NAME[/ARITY] \| aliases MOD FILES` | grep that knows the code: alias-aware calls, defs, aliases; strings/comments never match | LANDED |
| `refs Mod.fun/arity` | every call site, precisely (Expert) | needs the Expert client |
| `menard.snapshot ROUTE\|COMPONENT` | what the code RENDERS: the HTML snapshot + axe + LiveView-rule findings, via excessibility (Andrew's package) — an agent reads the output of the UI code it just edited, no browser | waits for a Phoenix app in the repo (the web UI) |

Run and update (`mix menard.run VERB`, one JSON line, exit 1 when not ok — LANDED · MCP `run_verb`):
`check`, `test [FILE[:LINE]]` (each failure as data: name, module, at, code/left/right or error,
and the test's own `source`; the tail is ExUnit's summary, not the logs), `format [FILES]`,
`compile`. Still plain mise tasks: `deps.get`,
`deps.update PKG`, `release`, `restart`.

Scoping (LANDED): every MCP verb resolves paths under the calling thread's worktree
(`Server.Source.Tools`) and refuses a path outside it; the reviewer archetype's profile excludes
the edit verbs (`rename_identifier`, `edit_clause`) and keeps introspection + run.

## Shape

- `Menard.Rename` exists. Next modules: `Menard.Clause` (delete/insert/replace),
  `Menard.Outline`, `Menard.Refs` (Expert client), all `@spec`'d, all tested on
  source strings (no files) plus one file-level test per mix task.
- The MCP verbs ride the existing machine-scope tool surface (`Console.Profiles` cuts them per
  archetype: a reviewer gets introspection only; a builder gets edits; the gates run for everyone).
- Every edit verb: `{:ok, diff, compile: :ok | {:error, diagnostics}}` — the coworker sees what it
  did and whether it still builds, in one turn.
- The console's drawer gets an OUTLINE pane for the open thread's worktree files (later).

## Order

1. DONE 2026-09-08: `menard.rename --comments`, `menard.outline`, `menard.diagnostics`, `menard.inspect`.
2. DONE 2026-09-08: clause verbs (`Menard.Clause`), `menard.run`, MCP exposure with the
   reviewer cut.
3. Expert client (`refs`, `rename-refs`, `move-def`) — depends on the adapters' lspd being stable.
4. `add-alias`/`add-import`; the console's OUTLINE drawer pane; the tlon-shaped `/implement` runs
   on these.
5. A standalone Menard MCP (stdio, Anubis, cwd-scoped, no identity) for harnesses outside tlon —
   Claude Code and a bare pi — exposing the SAME `Menard.*` functions and nothing else. Menard the
   library stays a library; tlon's MCP stays the coworkers' scoped door (Andrew, 2026-09-08:
   "is/should menard be an mcp?").

Ties to `2026-09-08-tlon-shaped-flows.md` (the implement skill's toolbox) and the value-loop plan
(review coworkers read `refs`/`diagnostics`, not raw diffs).
