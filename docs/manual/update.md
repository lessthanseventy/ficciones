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

- **home:switch** — the home-manager profile, from the commit it runs on: every rendered theme
  file, the Hyprland config and `~/.config/mise/config.toml` (store files, so a checkout or an
  edit changes nothing live until the next switch), `~/.config/nvim` → nvim-config, user
  packages, the shell package, git hooks (`core.hooksPath` → `scripts/git-hooks`). From a
  checkout with uncommitted changes its first line says so, and lists them. A running tmux server
  re-reads a changed `tmux.conf`.
- **shell:restart** — the astal shell user unit (`Restart=on-failure`; the idle inhibitor is a
  logind FD, so a restart drops and re-takes it).

Live-editable without any of that: nvim-config (`~/.config/nvim` is the repo), the shell from
source (`mise run shell:dev`).
