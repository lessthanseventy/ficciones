# Sovereign repos + aleph as the life TUI — design

**Date:** 2026-09-25
**Status:** designed; no code moved yet. Sequenced in §6, each step gated by a check.
**Asked:** Andrew wants tlön and menard (and aleph) to run outside ficciones — on the work Mac —
and aleph to become the life app it was meant to be. Orbis: ditch it? One life app or three?

Supersedes the **one-cockpit + world-types** model in `2026-08-21-worlds-orbis-reshape-design.md`
and the **aleph = the one cockpit** framing in `2026-08-14-aleph-cockpit-and-elixir-spine.md`.
Leaves `2026-09-25-tlon-master-plan.md` intact: Tlön stays one always-up brain with one primary dev
surface — it moves house, it doesn't change shape.

---

## 0 · North star

> **ficciones is the machine; the apps it runs live in their own repos and run anywhere.**
> `tlon` is the dev product (brain + cockpit + harness adapters), `aleph` is the life TUI over the
> same brain, `menard` edits Elixir. ficciones pins each and wires it into the home box; the work
> Mac clones them without ficciones.

```
 own repos (run on any box)                          ficciones (home machine only)
 ┌──────────────────────────────┐  ┌──────────┐      ┌─────────────────────────────┐
 │ tlon                         │  │ menard   │      │ flake · home-manager · os   │
 │  server/   the brain (funes@)│  │ Elixir   │      │ desktop · agents · secrets  │
 │  console/  the dev cockpit   │  │ AST verbs│      │ pins tlon/aleph/menard,     │
 │  adapters/ pi + Claude Code  │  └──────────┘      │ wires them into this box    │
 └──────────────┬───────────────┘                    └─────────────────────────────┘
                │ erpc (Console.Backend.Remote's seam)
         ┌──────┴───────┐
         │ aleph        │
         │ the life TUI │
         └──────────────┘
```

The rule that keeps repos from becoming separate computers is unchanged: **every client reads the
same `Server.*` contexts and Bus topics on the one server.** No client owns truth.

## 1 · The decision

**Two apps over one brain**, because the dev loop and the life loop have different verbs (`read /
edit / prove with a test` vs `capture / recall / revisit`), and forcing both through one TUI is the
conflation that kept the design circling. The dev app already exists; the life app is new.

**But three repos move, not four.** `server`, `console` and `adapters` leave ficciones *together*,
as one `tlon` repo, because they are one product today and the seams between them are compile-time:

- `modules/console/mix.exs` depends on `{:server, path: "../server"}`, and console calls `Server.*`
  directly (`Console.Backend.Local`, mix tasks, `mention.ex`, `orchestrator.ex`, `lazygit.ex`).
- `adapters/` briefs, gates and registers against the server's MCP and names server modules;
  `scripts/check-names.sh` is what keeps those names honest, and it only works inside one tree.
- The live system is already named `tlon` end to end — `tlon.service`, the `tlon`/`tlon_dev`
  databases, `TLON_*` env, the `tlon` MCP and launcher. One `tlon` repo inherits those names;
  splitting server off as "funes" would mean renaming the service, the databases and the env.

Splitting them into separate repos buys nothing the goal needs and costs a dependency split, a
rename, and the loss of the one gate that catches cross-seam breakage. The repo boundary goes where
the coupling is weakest: between the machine and the product, and between tlon and aleph.

## 2 · Names

| name | Borges | in this design |
|---|---|---|
| **tlön** (`tlon`) | *Tlön, Uqbar, Orbis Tertius* — an invented world | the dev product: server + cockpit + adapters. Already the product name. |
| **funes** | *Funes el memorioso* | stays what it is — the server's node (`funes@127.0.0.1`) and the memory's story. Not a repo. |
| **aleph** | *The Aleph* | **the life TUI.** Narrower than the Borges point-that-sees-all; accepted, not reopened. |
| **menard** | *Pierre Menard* | the Elixir AST toolbox; already its own repo. |
| ~~orbis~~ | | **dropped** (§3). |
| **ficciones** | the collection | the machine that holds the stories. |

No code rename falls out of this. `console` stays the cockpit app's name inside `tlon`;
`Console.Tlon.Focus` stays where it is.

## 3 · Orbis — dropped

Orbis was the god-view of the one cockpit, surveying every world because every world lived in one
app. With two apps and two attention modes, a single glance over dev threads and a life journal is
almost never wanted. A cross-cutting look, if ever needed, is a query against the server, not a
layer or a repo.

## 4 · aleph — one app, view-modes within it

Journal, finances and notes share the brain, the verbs and the terminal; they differ in content
type and panel set. So: **one app; each is a view-mode** — a declared struct with a fixed panel
set, the same shape as the cockpit's workspaces, so a view-mode can't quietly grow knobs.

aleph opens on a **Home dashboard** (a neovim-start-page feel): recent journal entries, an open
finance question, pinned notes, with a hotkey into each view-mode. It surveys only aleph's own
surfaces, so it is not Orbis back; the label is plain `Home`.

What exists to start from, measured: **Notes only.** `Server.Notes` / `Server.Note` (data, in the
server) and `Console.Panel.NoteBoard` (the panel, in the cockpit). There is no journal or finances
code anywhere — those are new builds, not migrations.

aleph reaches the brain the way the cockpit already can: over erpc to `funes@`, the seam
`Console.Backend.Remote` proves (a call while the link is down raises `ServerDown` and degrades to
stale panels, not a dead frame). For its `Server.*` calls to fail at compile time rather than at
runtime after a server rename, aleph's test env compiles against the server as a pinned git dep
(`{:server, git: …tlon, sparse: "server", only: :test}`); bumping the pin is when a rename shows up.

## 5 · What each piece is today

- **`modules/server/`** — the brain. Liftable by law already (`modules/server/AGENTS.md`: never
  imports up). Pins menard by tag in its own `mix.exs`.
- **`modules/console/`** — the TTY cockpit over the server; 25 panels; `Local` and `Remote`
  backends chosen in `config/runtime.exs`.
- **`modules/adapters/`** — pi extensions (pi, consult, lsp, lspd, reload, footer), the Claude Code
  hooks, the shared skills. `flake.nix` points at their source paths inside this repo
  (`${repo}/modules/adapters/…`) and at the server's release (`${repo}/modules/server/_build/…`).
- **`modules/os`, `modules/desktop`, `modules/agents`** — the machine. They stay.
- **`tasks/{server,console,adapters,pi}.toml`** — tlon's dev loop; they move with it.
  `tasks/desktop.toml` stays. `tasks/menard.toml` runs `~/projects/menard` and stays as the
  machine's door onto it.

## 6 · The sequence (each step gated; nothing "done" until its check is green)

0. **Quiesce.** Every master-plan piece in flight lands or parks; no coworker worktree open on
   server/console/adapters; no staffed leaf threads. Extraction strands any branch cut before it.
   *Check:* `git worktree list` shows only the main checkout; `mise run check` green on `main`.
1. **Extract `tlon`.** `git filter-repo` `modules/{server,console,adapters}` plus their tasks,
   scripts and gates into `~/projects/tlon`, history kept. ficciones takes it as a flake input;
   `flake.nix`'s `${repo}/modules/adapters/…` and `serverRel` paths point into the input; the
   systemd unit's release path follows. `check-names.sh` goes with tlon; ficciones keeps a smaller
   one for its own glue.
   *Check:* `mise run check` green in `tlon` standalone; `mise run check` + `mise run flake:check`
   green in ficciones; `mise run machine:update` brings the live server and cockpit back up from
   the input, and `server:roster` shows the cast.
2. **tlon on the work Mac.** The server needs Postgres and a supervisor that isn't
   `systemd --user` (launchd); its own database — work never reaches the home brain.
   *Check:* a fresh clone on the Mac: `mise run check` green, the server up under launchd, the
   cockpit attached to it.
3. **Birth aleph.** New repo; first content is `AGENTS.md` + the app with the Home dashboard and
   the Notes view-mode, over the erpc seam (§4). `Console.Panel.NoteBoard` moves out of the
   cockpit; `Server.Notes` stays in the server.
   *Check:* aleph's suite green, including its compile against the pinned server; aleph renders
   Notes from the live server; the NoteBoard is gone from the cockpit and tlon's suite is green.
4. **Journal, then finances** — new view-modes in aleph, named here and detailed when step 3 is
   green.

## 7 · Open

- **When to start step 0** — after which master-plan piece (`2026-09-25-tlon-master-plan.md`,
  A→G). Extraction mid-plan costs rebases for every open workline.
- **aleph's first view-mode** — Notes is recommended (the only one with code today). Journal or
  finances would be a from-scratch first build.
- **Mac install path** — home-manager on nix-darwin, or plain mise + Homebrew Postgres. Decided at
  step 2, not before.
- **aleph in the shell sidebar.** The master plan's piece G already builds the desktop sidebar —
  a reply box posting through `/api` and a terminal attached to a thread — as a client that owns
  nothing. A life chat tucked there is a second tab on that same sidebar pointed at an aleph
  thread, not a new MCP or a new app; it waits for G's design doc.
