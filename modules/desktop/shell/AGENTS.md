# modules/desktop/shell — the astal shell

AGS 3 (gnim JSX) over Astal, GTK4, SCSS. Design: `docs/plans/2026-09-02-astal-shell-design.md`;
where it runs and the VM: `docs/plans/2026-09-05-astal-shell-nixos-vm-plan.md`.

## Loop

- `mise shell:dev` — run from source on the live desktop (it replaces the running shell). Edit,
  Ctrl+C, rerun. Its styles are the working tree's in the bundled (uqbar) palette: `ASTAL_SHELL_DEV`
  skips the installed theme's compiled css, which would hide every style change until a home:switch.
- `mise shot:layer -- rail|bar|deck` — the shell draws in LAYERS, not windows, so `shot:window`
  cannot see it. **Verify a colour or layout change on a screenshot, not in the source**: a rule
  can be right in the file and reach nothing on screen (see the `*` selector below).
- `mise shell:check` — the gate: `ags bundle`, then tsc over our files. Both must pass; zero
  type errors is the bar, no error is "known" or ignorable.
- `mise shell:test` — node tests of the pure logic (`lib/*.test.mjs`, also the last step of
  `shell:check`). What they import must not touch `gi://`; split a module's pure half out
  (`settings-core.ts`) to test it.
- `nix build .#astal-shell` — the store package the VM and home-manager install.
- In the NixOS VM the unit is `astal-shell.service`; `mise shell:logs` / `shell:restart`.

## Rules

- **No hex in components, and name a ROLE, not a colour.** `style/_palette.scss` is GENERATED from
  `modules/desktop/theme` — never edit it; `_tokens.scss` forwards it and adds the metrics. The
  vocabulary: `$body` text · `$key` for anything you act on (controls, links, keys) · `$live`
  running or occupied · `$attention` agents and the operator · `$cursor-field` where you are,
  inverse video · `$sel-field` what you picked · `$max-contrast` what hover lifts to. The `$cat-*`
  tier is hues used as CATEGORIES (log sources, the per-card hue map) and nothing else. Colour
  names like `$amber` do not exist, so a stale one is a sass error. One font (`$font`).
- **A preference is a setting, not a constant or a private state file.** Add it to `DEFAULTS` in
  `lib/settings.ts` and read it with `setting(key)` (live; `astal-shell get`/`set` reach it).
  Where things are (pinned windows, frecency) is state and stays under `~/.local/state/astal-shell`.
- **`_tui.scss` opens with `* { color: $body }`, so a colour on a parent never reaches its
  children.** Set it on the `label` too, or the rule is correct in the file and dead on screen —
  which is how four hover states did nothing for a day.
- `tsconfig.json` is owned by `ags types -u` (it rewrites the file, comments included). Never
  add `experimentalDecorators`: gnim uses TC39 decorators and the legacy emit dies at startup
  with "meta is undefined" in dbus.ts.
- tsc over ags 3.1's own lib fails under TS 5.9 (decorator signatures, two GObject identities;
  a stock `ags init` project fails the same way), so `shell:check` filters errors inside
  `/nix/store` only. ags's `app` carries the other GObject identity: see it through gnim's
  (`app as unknown as GObject.Object & {…}`, app.tsx) rather than binding to it directly.
- Gtk4 `label.wrapMode` is `Pango.WrapMode`, not `Gtk.WrapMode`.
- Killing a running shell: `pkill gjs`. `pkill -f astal-shell` matches the calling bash and a
  surviving instance makes every new launch exit at once (dbus name taken).
