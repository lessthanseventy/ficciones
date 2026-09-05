# modules/desktop/shell — the astal shell

AGS 3 (gnim JSX) over Astal, GTK4, SCSS. Design: `docs/plans/2026-09-02-astal-shell-design.md`;
where it runs and the VM: `docs/plans/2026-09-05-astal-shell-nixos-vm-plan.md`.

## Loop

- `mise shell:dev` — run from source on the live desktop (alongside caelestia on Arch). Edit,
  Ctrl+C, rerun. Screenshot with `grim -o eDP-1 x.png` to see what the user sees.
- `mise shell:check` — `ags bundle` is the gate; tsc is advisory (see below).
- `nix build .#astal-shell` — the store package the VM and home-manager install.
- In the NixOS VM the unit is `astal-shell.service`; `mise shell:logs` / `shell:restart`.

## Rules

- No hex in components: every colour is a token in `style/_tokens.scss`. Amber body, green and
  pink highlights, `.chip` inverse video for the active thing. One font (`$font`).
- `tsconfig.json` is owned by `ags types -u` (it rewrites the file, comments included). Never
  add `experimentalDecorators`: gnim uses TC39 decorators and the legacy emit dies at startup
  with "meta is undefined" in dbus.ts.
- tsc over ags 3.1's own lib fails under TS 5.9 (decorator signatures, two GObject identities;
  a stock `ags init` project fails the same way), so `shell:check` filters `/nix/store` noise
  and does not block on the rest. Read the remainder; the `app.tsx` lines are that identity
  problem leaking through `createBinding(app, "monitors")`, same code as upstream's example.
- Gtk4 `label.wrapMode` is `Pango.WrapMode`, not `Gtk.WrapMode`.
- Killing a running shell: `pkill gjs`. `pkill -f astal-shell` matches the calling bash and a
  surviving instance makes every new launch exit at once (dbus name taken).
