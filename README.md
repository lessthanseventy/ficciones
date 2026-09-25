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

The AI stack — the server, the TTY cockpit (launched as `tlon`) and the agent adapters — is its own
repo, `~/projects/tlon`, so it runs on boxes that are not this one. This machine runs it: the flake
starts its server as a `systemd --user` service and points pi and Claude Code at its adapters.

## Layout

```
ficciones/
  flake.nix            # the installer — Nix + home-manager, adopted gradually (see below)
  mise.toml            # the shared dev loop — every task the human and the agents run
  scripts/             # the shell side of that loop (cap, watch, the theme and manual generators)
  modules/
    agents/            # the rules every agent on this machine works by
    desktop/           # hyprland + its stack
    os/                # the NixOS side
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
- `~/projects/tlon` — the AI stack: its `README.md`, and `server/docs/spec.md`, the specification that
  is the reason any of this exists.
