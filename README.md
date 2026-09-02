# ficciones

One person's computer, as a repository. Dotfiles, installer, desktop, and the AI stack — the whole
machine declared in one place so it can be rebuilt on any box, or a throwaway VM, and be the same
machine when it comes back up.

This started life as the `server` specification (the AI stack) and grew outward: if the goal is a
computing life you can trust and rebuild, the repository has to be the machine, not one program on it.

**The name.** Borges' *Ficciones* is the 1944 collection that gives this repository its name — a
collection of stories, and this repo a collection of modules. The AI stack it grows is named for one
story in it: **Tlön**, from "Tlön, Uqbar, Orbis Tertius" (1940), where scholars find an encyclopedia of
an invented planet and, as they study the fiction, it bleeds into reality and overwrites it. That is
exactly what the product does — you author a fictional organization (a cast of agents, workspaces,
knobs) and, through use, it becomes real work in your actual repo. The fiction overwrites reality.

## Tlön

Tlön is **many UIs over one memory** — a communication, planning, and coordination surface for a crew
of AI agents. Three internal apps make it up, named for what they do:

- **`server`** — the shared spine: the data model, the communication bus, the single-writer discipline,
  the always-up MCP channel. (The memory concept is *Funes the Memorious* — the man who could not
  forget — living on in the recall engine.)
- **`console`** — the TTY cockpit that renders the spine: workspaces, threads, the crew, embedded
  terminals. (The seeing-everything-at-once concept is *The Aleph*.) Launched with the `tlon` command.
- **`adapters`** — the hands: how a working agent (Claude Code, pi) reaches the spine, wakes up already
  knowing its thread, and banks what it learns.

A **workspace** is a project inside Tlön (this repo's own is *ficciones*). The crew keep their Borges
names — **tertius** (the Orbis Tertius meta-agent), **hronir** (the builder). Cute names only for
things with personality; everything else is called what it is.

## Layout

```
ficciones/
  flake.nix            # the installer — Nix + home-manager, adopted gradually (see below)
  mise.toml            # the shared dev loop — every task the human and the agents run
  scripts/             # the shell side of that loop (cap, watch, the reaper, the tlon CLI)
  modules/
    server/            # the spine — its own spec, its own boundary; the first module built
    console/           # the TTY cockpit, launched as `tlon`
    adapters/          # the hands: pi extensions, the Claude Code launcher + hooks, skills
    desktop/           # hyprland + its stack
  secrets/             # agenix-encrypted machine secrets
  docs/plans/          # design records, most recent first
```

The rest of the environment (theme, shell, dotfiles) is pulled over incrementally — Nix makes that
gradual, so there is no big bang, and empty directories are not created to pretend otherwise: a
module is born when it has content.

## The installer

Nix, on the existing Arch install, adopted the low-blast-radius way: **Nix + home-manager as a flake**
manages home declaratively while Arch and `mise` stay exactly where they are. A **disposable NixOS VM**
(`nixos-rebuild build-vm`) is the testbed where full NixOS gets tried before it ever touches metal.
The reasoning — and why the old "Arch/AUR + mise beats NixOS" verdict was correct until the AI world
changed one term of it — is in `docs/plans/2026-08-14-machine-v2-and-funes-design.md`.

`mise run flake:check` (evaluate + build the activation package) is fair for anyone, human or
agent, to run; the system-mutating step — `mise run home:switch` — stays the human's, because
building the machine is a change the human owns.

## Where to start reading

- `docs/plans/2026-08-14-machine-v2-and-funes-design.md` — the machine-level design and every decision behind it.
- `modules/server/README.md` — the AI stack, and where its name comes from.
- `modules/server/docs/spec.md` — the specification that is the reason any of this exists. Read it before
  writing anything in that module.
