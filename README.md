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
  flake.nix            # the installer — Nix, adopted gradually (see below)
  hosts/               # per-machine composition: which modules a host turns on
  modules/
    server/             # the AI stack — its own spec, its own boundary; the first module built
    desktop/           # hyprland + its stack        (harvested from the current env, later)
    theme/             # colours, UI prefs, theming    (harvested, later)
    shell/             # shell, ghostty, dotfiles        (harvested, later)
  docs/plans/          # design records, most recent first
```

Only `modules/server/` exists as a real module today. The env modules are a separate, incremental track —
Nix makes pulling them over gradual, so there is no big bang, and empty directories are not created to
pretend otherwise: a module is born when it has content.

## The installer

Nix, on the existing Arch install, adopted the low-blast-radius way: **Nix + home-manager as a flake**
manages home declaratively while Arch and `mise` stay exactly where they are. A **disposable NixOS VM**
(`nixos-rebuild build-vm`) is the testbed where full NixOS gets tried before it ever touches metal.
The reasoning — and why the old "Arch/AUR + mise beats NixOS" verdict was correct until the AI world
changed one term of it — is in `docs/plans/2026-08-14-machine-v2-and-server-design.md`.

Nix commands are run by the human, not by an agent in this repo: on this machine the tool sandbox
segfaults the `nix` binary, and building a machine is a system change the human owns anyway.

## Where to start reading

- `docs/plans/2026-08-14-machine-v2-and-server-design.md` — the machine-level design and every decision behind it.
- `modules/server/README.md` — the AI stack, and where its name comes from.
- `modules/server/docs/spec.md` — the specification that is the reason any of this exists. Read it before
  writing anything in that module.
