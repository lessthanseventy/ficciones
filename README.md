# ficciones

One person's computer, as a repository. Dotfiles, installer, desktop, and the AI stack — the whole
machine declared in one place so it can be rebuilt on any box, or a throwaway VM, and be the same
machine when it comes back up.

This started life as the `funes` specification (the AI stack) and grew outward: if the goal is a
computing life you can trust and rebuild, the repository has to be the machine, not one program on it.

**The name.** Borges' *Ficciones* is the 1944 collection that contains the story "Funes the Memorious."
This repository contains the `funes` module exactly as that book contains that story — so the repo is
*ficciones*, and each module is another story in it: `funes` is memory (the man who could not forget).
The AI environments the stack grows carry the same Borges naming — see **The environments** below. A
naming system, not just a name.

## The environments

The AI stack is **many UIs over one memory**. `funes` is the shared spine — the data model, the
communication bus, the single-writer discipline; `aleph` (from "The Aleph", the point that contains all
points) is the cockpit that renders it. Over that spine sit the *environments* — each a bounded domain
with its own data, its own coworkers, and its own surface, and each named for the Borges story it
behaves like. **None exist yet** — a module is born when it has content, and these are being designed,
not built — but the vocabulary is fixed:

- **`congress` → Chat.** *The Congress* (1971): a secret society tries to convene an assembly
  representing every human alive, and finally realises the Congress already exists — it is the world
  itself, always in session. The always-on assembly of all your coworkers; the conversation doesn't need
  convening, it just *is*.
- **`senderos` → Board.** *The Garden of Forking Paths* (1941): a labyrinth that turns out to be a novel
  where every choice takes *all* paths at once, time branching endlessly. Every ticket is a fork — a
  branch of work that could be taken; the board is the garden of the paths in flight.
- **`tlön` → Workbench.** *Tlön, Uqbar, Orbis Tertius* (1940): scholars find an encyclopedia of an
  invented planet, and as they study the fiction it bleeds into reality and overwrites it. This is the
  dogfood environment — building a fictional system, in a repo named *ficciones*, that becomes the real
  one you work inside.
- **`zahir` → Support.** *The Zahir* (1949): an ordinary coin that, once seen, cannot be forgotten, and
  grows until it blots out the world. The incident that won't let go, the page that eclipses all other
  work until it clears. A support queue is a nest of Zahirs.
- **`compass` → Review.** *Death and the Compass* (1942): a detective reads murders as points on a
  compass and follows the pattern with beautiful rigor to its end — which was a trap laid for him.
  Tracing a change to its source with the detective's discipline, and a knowing nudge that the most
  elegant reading can be the wrong one.

## Layout

```
ficciones/
  flake.nix            # the installer — Nix, adopted gradually (see below)
  hosts/               # per-machine composition: which modules a host turns on
  modules/
    funes/             # the AI stack — its own spec, its own boundary; the first module built
    desktop/           # hyprland + its stack        (harvested from the current env, later)
    theme/             # colours, UI prefs, theming    (harvested, later)
    shell/             # shell, ghostty, dotfiles        (harvested, later)
  docs/plans/          # design records, most recent first
```

Only `modules/funes/` exists as a real module today. The env modules are a separate, incremental track —
Nix makes pulling them over gradual, so there is no big bang, and empty directories are not created to
pretend otherwise: a module is born when it has content.

## The installer

Nix, on the existing Arch install, adopted the low-blast-radius way: **Nix + home-manager as a flake**
manages home declaratively while Arch and `mise` stay exactly where they are. A **disposable NixOS VM**
(`nixos-rebuild build-vm`) is the testbed where full NixOS gets tried before it ever touches metal.
The reasoning — and why the old "Arch/AUR + mise beats NixOS" verdict was correct until the AI world
changed one term of it — is in `docs/plans/2026-08-14-machine-v2-and-funes-design.md`.

Nix commands are run by the human, not by an agent in this repo: on this machine the tool sandbox
segfaults the `nix` binary, and building a machine is a system change the human owns anyway.

## Where to start reading

- `docs/plans/2026-08-14-machine-v2-and-funes-design.md` — the machine-level design and every decision behind it.
- `modules/funes/README.md` — the AI stack, and where its name comes from.
- `modules/funes/docs/spec.md` — the specification that is the reason any of this exists. Read it before
  writing anything in that module.
