# What Ficciones is

Ficciones is the human's machine and the shop where Claudes work on it: one Arch laptop with a Nix
flake (home-manager) above it for the desktop and dotfiles, and the tools Claudes work through. It is
four repos, all under `~/projects`. Hold any design or build to [the principles](principles.md).

## The four repos

- **ficciones** (`~/projects/ficciones`): the machine, the desktop and the agent wiring, as modules
  under `modules/`. It is where the shared mise tasks live (`mise tasks`), and `mise run check` is its
  gate. Docs: `README.md`, `AGENTS.md`, `docs/manual/`.
- **arena** (`~/projects/arena`): the Zig TUI where the human watches and steers: tmux windows as
  columns, each Claude's state, the plan and the board. Docs: `AGENTS.md`, `README.md`,
  `docs/what-arena-is.md`.
- **babylon** (`~/projects/babylon`): tickets for every Claude session on the machine, and the
  pipeline that lands them: rebase, gate, review, land, install. Also auto and the orchestrator.
  Docs: `README.md`, `AGENTS.md`, `orchestrator.md`.
- **menard** (`~/projects/menard`): Elixir (and other) editing and test tooling that every session
  edits and runs through. Docs: `README.md`, `AGENTS.md`, `skills/menard/SKILL.md`.

## How they fit

A Claude claims a babylon ticket and works it in its own worktree, editing and testing through
menard. It submits the ticket and babylon gates, reviews and lands it. arena shows the human what each
Claude is doing and lets them answer. ficciones installs all of it onto the machine and wires the
agents.

It grew from tlon, which is being archived: arena took tlon's good parts, and babylon was pulled out
of arena.
