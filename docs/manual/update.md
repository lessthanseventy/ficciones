# Updating the machine

One verb applies the checkout to the running machine, in dependency order:

```
mise run machine:update      # home:switch → shell:restart → server:restart
```

Moving the pins is a separate, committable step — `mise run flake:bump` (nix inputs + the
hand-pinned packages) — then `machine:update` applies it. Gates before either:
`mise run check` (server, adapters, office), `mise run flake:check` (the machine closure),
`mise run manual:check` (this manual).

What each step touches:

- **home:switch** — the home-manager profile: every rendered theme file, the out-of-store
  links (`~/.config/hypr/hyprland.lua`, `~/.config/nvim` → asterion), user packages, the shell
  package, git hooks (`core.hooksPath` → `scripts/git-hooks`).
- **shell:restart** — the astal shell user unit (`Restart=on-failure`; the idle inhibitor is a
  logind FD, so a restart drops and re-takes it).
- **server:restart** — rebuilds the release and restarts `tlon.service`; coworkers' MCP
  connections re-mint their tokens on reconnect (`/mint`), so nothing is stranded.
  The store is Postgres `tlon` on the local socket (since 2026-09-18); the release migrates it
  on start. `mise run server:dev` uses `tlon_dev`; the suites create `tlon_test` and
  `tlon_console_*` themselves — a local Postgres is a prerequisite for `mise run check`.

Live-editable without any of that: `hyprland.lua` (hyprctl reload on save via the git hooks),
asterion (`~/.config/nvim` is the repo), the shell from source (`mise run shell:dev`).
