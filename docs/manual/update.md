# Updating the machine

One verb applies the checkout to the running machine, in dependency order:

```
mise run machine:update      # home:switch → shell:restart
```

Moving the pins is a separate, committable step — `mise run flake:bump` (nix inputs + the
hand-pinned packages) — then `machine:update` applies it. Gates before either:
`mise run check`: the names gate, the cap hook's test, `manual:check` (this manual) and
`flake:check` (the machine closure).

What each step touches:

- **home:switch** — the home-manager profile: every rendered theme file, the out-of-store
  links (`~/.config/hypr/hyprland.lua`, `~/.config/nvim` → nvim-config), user packages, the shell
  package, git hooks (`core.hooksPath` → `scripts/git-hooks`).
- **shell:restart** — the astal shell user unit (`Restart=on-failure`; the idle inhibitor is a
  logind FD, so a restart drops and re-takes it).

Live-editable without any of that: `hyprland.lua` (hyprctl reload on save via the git hooks),
nvim-config (`~/.config/nvim` is the repo), the shell from source (`mise run shell:dev`).
