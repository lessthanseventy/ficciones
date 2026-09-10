# Working on Elixir with Menard

This plugin installs a `PreToolUse` hook that **blocks `Edit` and `Write` on any `.ex`/`.exs`
holding a `defmodule`**. Use the verbs instead: they parse the file, change the tree, and
parse-check what they write, where a text substitution is a guess whose failures are silent.

Exempt: new files, `_build/`, `deps/`, `config/*.exs`, `.formatter.exs` — creation, or bare keyword
lists the verbs have nothing to say about. **`Bash` is not watched, and that is not permission** —
`sed -i` on a module is just as wrong, it is only unenforceable.

## Which verb

Read the file first — `outline FILE` names every module, clause and doc in it. Then match the
SHAPE of what you are changing, not the size of the change:

| you are changing | verb |
|---|---|
| what a function does | `clause replace FILE name/arity HEAD BODY` |
| its head, args or guard | `clause rewrite FILE name/arity HEAD 'def …'` |
| one expression inside it | `stmt replace FILE name/arity HEAD MATCH CODE` |
| a whole clause's existence | `clause insert-after` / `insert-before` / `delete` |
| which FILE a function lives in | `clause move FILE name/arity --to DEST [--as Mod.Name]` |
| a module attribute (`@colors`, `@hints`) | `attr get\|set\|delete\|list FILE @name` |
| the comment above one | `attr comment FILE @name [TEXT]` — no TEXT removes it |
| a `do` block by its label — an ExUnit `test`, a `describe` | `block get\|replace\|add\|relabel FILE test --label "…"` |
| an alias/import/require/use | `directive add\|remove\|list FILE KIND MOD` |
| a name, everywhere | `rename OLD NEW [--atoms] [--comments] FILES` |

`replace` takes the **body**; `rewrite` takes the **whole clause**. Passing a `def` to `replace` is
refused, because `def bg, do: def(bg, do: X)` is valid Elixir and only the compiler would object.

What the verbs guarantee, where it is not obvious from the name:

- `stmt` reaches a line in a `do` block, a step in a `with`, and a `case` **arm** alike — address
  the clause, then the statement by what is WRITTEN. `list` prints what is there, and so does a miss.
- `clause insert-at` is for a whole new FUNCTION, which has no sibling to anchor to; placement
  follows the code, a `defp` landing with the private functions. A new *clause* of an existing
  function is `insert-after`, named against its sibling.
- `clause visibility` flips EVERY clause at once — a half-flipped function does not compile.
- `directive add` places in Elixir's conventional order (use → import → alias → require,
  alphabetised), so the next format pass does not move it.
- `block --in PARENT` appends inside a labelled block or a MODULE. A schema field lives here
  (`block replace FILE schema … --label <table>`), not in the clause verbs.
- `attr` refuses a name that repeats per clause (`@doc`, `@impl`, `@spec`) — the clause verbs
  already carry those.
- `find calls|defs|aliases` is grep that knows the code: strings and comments never match.
- `write FILE CODE` (`-` reads stdin) refuses Elixir that does not parse, before it reaches disk.
  For a NEW module, or a rewrite so total that patching is the wrong tool.
- `clause move` carries the function's `@doc`, `@spec` and the comment above it, and takes EVERY
  clause — half a function in each file is the mistake `visibility` refuses. It creates a missing
  destination, naming the module after the path the way a generator would (`--as` overrides). It
  does NOT touch aliases or call sites: that is the judgement, and `deps` is how you make it.
- `deps FILE name/arity` reports what a function references: local calls and who else calls them,
  remote calls, the aliases that must travel, the attributes that will not. **The read before
  moving code.**

## What no error can tell you

- **ExUnit `test` and `describe` are macros, not definitions.** The clause verbs cannot address
  them; `block` can, by macro name with `--label`. `clause insert-at FILE <Module> bottom CODE`
  adds a new test — name the module, since a test file usually holds several.
- **A zero-arity clause has no head.** `bg`, `bg()`, `def bg` and `""` all address it.
- **An ambiguous head is refused, not guessed at** — `--nth 1..N` says which. Acting on "the
  first" silently is how a delete eats the clause that was just written.
- **`delete` takes the clause's `@doc`/`@spec` with it**, and `insert-before` goes above them.
  A `@doc` attaches to whatever definition *follows* it, so anything landing between the two
  would take the doc with it.
- **Editing menard with menard:** `--frozen` runs the last build straight off `_build`, with no
  compile step. Without it, a half-applied edit stops the project compiling and the tool locks
  itself out of finishing its own change.

## Before you are done

`run [--in DIR] check` — format, warnings-as-errors, tests, in one call. `run test` and
`run compile` answer the same way: one line, `{"ok":…,"tests":…,"failures":[…]}`, each failure
carrying its source, rather than output to grep. A bare `mix test` gets a nudge toward this from a
`PostToolUse` hook — advisory, since the command has already run.

Menard's verbs format after every edit, so the formatter's output is what your next read shows; a
`--check-formatted` failure at the gate should never be the first you hear of it.

A parse-checked write catches **malformed** output, not **wrong** output. It is a floor, not a
proof: run the check.
