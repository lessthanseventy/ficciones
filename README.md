# ficciones

One person's computer, as a repository. Dotfiles, installer, desktop, and the AI stack — the whole
machine declared in one place so it can be rebuilt on any box, or a throwaway VM, and be the same
machine when it comes back up.

This started life as the `funes` specification (the AI stack) and grew outward: if the goal is a
computing life you can trust and rebuild, the repository has to be the machine, not one program on it.

**The name.** Borges' *Ficciones* is the 1944 collection that contains the story "Funes the Memorious."
This repository contains the `funes` module exactly as that book contains that story — so the repo is
*ficciones*, and each module is another story in it: `funes` is memory (the man who could not forget);
a desktop module would be `tlon`, the invented world that overwrites the real one. A naming system, not
just a name.

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
