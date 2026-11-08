# How to work — four rules for any agent on this machine

Installed by the flake as `~/.claude/CLAUDE.md`; the source is
`modules/agents/how-to-work.md` in ficciones. Repo law lives in each repo's `AGENTS.md`.

1. **Think before coding.** Say the assumptions you are making and the tradeoff you picked; when
   two readings of a request lead to different work, ask, don't guess silently. If you are not
   sure, say so, in one line.
2. **Simplest thing that works.** The minimum code that meets the need. No speculative
   abstraction, no configurability nobody asked for, no "while I'm here". Three similar lines beat
   a helper written for a fourth caller that doesn't exist.
3. **Surgical changes.** Touch only what the task needs. Don't reformat, rename, or "clean up"
   adjacent code in the same change; if it deserves it, say so and do it as its own small commit.
   Every line you change should trace to the ask.
4. **Goal-driven.** Turn the task into a check you can run — a test, a gate, a screenshot diff, a
   command that goes red before and green after — then loop until it passes. Evidence, not
   assertion: show the command and its output. If it cannot be verified, say it is unverified.

Habits that follow: small commits as you go; comments carry the load-bearing *why* only; nothing
is called "known" or "ignorable" — fix it or name it as open.

**Linear history, every repo.** Rebase, then fast-forward — never a merge commit (git here is set
`merge.ff=only`, `pull.rebase=true`). A change bigger than one review is a stack of small PRs, each on
the last: `gh stack` (GitHub's stacked PRs) where the repo is on GitHub, plain branches with
`git rebase --update-refs` otherwise. Bring a branch up to date by rebasing it onto main, not by
merging main in. Rewriting history that is already pushed or shared is the human's call — ask.

## Code standards, every language

- **Comments default to none.** Write one only for a *why* the code cannot carry (a non-obvious
  constraint, an outside system's quirk, a deliberate trade-off), in one or two lines.
- **No history in the code.** Ticket or issue keys, incident stories, PR history and "used to / now /
  added for" narration stay out of code, tests, config and `@doc` text; they belong in the commit
  message and the PR description.
- **Don't narrate.** No restating what the code does, a test's name, or other call paths in prose.
  Match the file's comment density; a diff that adds more comment lines than code lines is wrong. In
  a review, comment creep is a finding.

## Elixir

- **Through menard, not bare mix, sed or grep.** Every Elixir edit and run goes through
  `~/projects/menard/bin/menard` (the same verbs as its MCP tools; `--help` on a verb shows its
  input). It formats every file it writes, so there is no separate format step. Which verb fits
  which change, and its traps: menard's skill (`skills/menard/SKILL.md`).
  - Several replacements, in one file or many, are one `edit`: each text found exactly once or
    nothing is written; `--then compile`, or `--then test` on the change's last edit.
  - `rename` for a rename across files; `find calls Mod.fun` for callers; `outline` then
    `clause get` to read one function from a big file; `clause move`/`split` to move code with its docs.
  - While working, `run test <files>` of what you changed. Once, when the change is done,
    `run check`: format, warnings as errors and the whole suite. `run credo --changed` holds the
    repo's Credo rules (`.credo.exs`) on the lines you touched.
  - Each run answers one JSON line with every failure's file, line and message: read it, never
    re-run to see more.
- Every public function you add or change has `@doc` and `@spec`.
- Pattern matching over conditionals where appropriate.
- **Avoid the anti-patterns in Elixir's own guide** (hexdocs.pm/elixir, "Anti-patterns"), above all:
  - assertive code: `map.key` and `%{key: v} = map` for keys that must be there, not `map[:key]` and
    a silent `nil`; match the shape you expect and let anything else crash;
  - non-assertive truthiness: `and`/`or`/`not` when the values are booleans, not `&&`/`||`;
  - boolean obsession: one atom (`:admin | :editor`) over several flags that can't all be true;
  - an option that changes the return type: write a second function instead;
  - exceptions for control flow: return `{:ok, _}`/`{:error, _}`, keep `raise` for bugs, and offer
    the `!` variant only beside the tuple one;
  - complex `else` clauses in `with`: tag or normalise errors at the source so `else` stays short;
  - `String.to_atom/1` on outside input (atoms are never collected);
  - a multi-clause function whose clauses do unrelated things: split it.

## Corrections that hold everywhere

- **A flaky test gets fixed, never re-run to green.** Find the nondeterminism and fix it.
- **Second sighting, root cause.** A bug or quirk seen twice gets its cause found and fixed at the
  source, not another workaround. That includes your own tooling.
- **Check the read before a write.** In a read-modify-write over many items, assert each read
  returned what you expect (status, non-empty) and stop on the first miss; dry-run the first item.
- **Verify state before building on it.** A "merged" or "closed" notice is not proof: fetch and look
  for the code on `origin/main`.
- **Wait on notifications, not loops.** Start a long command once in the background and wait for its
  completion; no `sleep`/`until` poll loops (they outlive you, and `pgrep -f` matches the loop
  itself). Before saying nothing is running, check your agents and background shells too.
- **The shell is zsh.** An unquoted `$var` is not word-split, so never keep a command in a variable;
  use a function.
- **Subagents get an explicit model** matched to the work: sonnet for specified builds, reviews and
  triage, haiku for one-liners; the top model only when the task needs it.
- **Report long runs as they go:** one line per milestone, not silence until the end.
