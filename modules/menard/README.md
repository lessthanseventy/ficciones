# Menard

> Pierre Menard, author of the Quixote: rewrite a text word for word and have it come out
> different.

AST-aware editing for Elixir. Every verb parses the file, changes the tree, and parse-checks what
it writes — so a half-applied edit is impossible, and only the bytes a verb names move
(Sourceror patches, not a reformat of the whole file).

It runs as a project of its own, which means `menard` keeps working on a codebase that does not
currently compile — the case where you most need it.

## Verbs

```
outline FILE                                   what is in the file
find PATTERN FILES                             where a thing is
deps FILE name/arity                           what a function calls
attr    get|set|delete|list  FILE NAME [VALUE]
attr    comment FILE NAME [TEXT]                the # comment above a table
clause  replace|rewrite|delete|insert-after|insert-before  FILE name/arity HEAD [CODE] [--nth N]
clause  insert-at FILE (Mod|-) top|bottom CODE
clause  doc|comment FILE name/arity HEAD [TEXT]
clause  visibility FILE name/arity public|private
stmt    insert-after|insert-before|replace|delete|list  FILE name/arity HEAD MATCH [CODE]
block   get|replace|add|relabel|list  FILE NAME [CODE]
module  add|list FILE [CODE]
directive add|remove|list FILE KIND MOD
rename  OLD NEW [--atoms] [--comments] FILES
write   FILE CODE
run     [--in DIR] check|test|format|compile
inspect [--in DIR] callers|exports|deps
diagnostics [--in DIR]
mcp                                            the same verbs over MCP
```

`--frozen` runs the last build straight off `_build` with no compile step: the escape hatch for
editing menard *with* menard, where a half-applied edit would otherwise lock the tool out of
finishing its own change.

## Claude Code plugin

`.claude-plugin/plugin.json` and `hooks/hooks.json` make this directory a plugin. Two hooks:

- **`menard-only.sh`** (`PreToolUse`) blocks `Edit`/`Write` on any `.ex`/`.exs` holding a
  `defmodule`. It passes new files, `_build/`, `deps/`, `config/*.exs` and `.formatter.exs` —
  menard has no verbs for a bare keyword list, so those are edited directly. It does not watch
  `Bash`: a shell command has no structured target, and matching the command text blocks anything
  that merely quotes the pattern. Precision over coverage — a guard that fires on innocent
  commands gets switched off.
- **`format-elixir.sh`** (`PostToolUse`) formats whatever was written with the file's *own*
  project formatter, plugins included, so the formatter's output is what the next read shows.

The guard exists because the rule "use menard for Elixir" was written down and then broken inside
the hour. A rule an agent has to remember is a rule it breaks.
