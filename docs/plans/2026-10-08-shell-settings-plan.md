# Shell settings: one store, one menu, and a jank pass

Every preference the shell has, in one place you can see and change. Today each feature saves (or
forgets) its own state its own way, and the rest are constants in the source.

## Decided (Andrew, 2026-10-08)

- **A file the menu writes**, not nix options: `~/.config/ficciones/shell.json`. Changes apply
  live and survive restarts; nix supplies only the defaults. (`~/.config/astal-shell/config.json`
  stays what it is — home-manager's read-only wallpapers/location.)
- **Its own Settings surface**, opened by a keybind (Super+Comma) and by Super+Shift+click on the
  dashboard's Aleph.
- Perf first (done: hacks at half size, smooth ambients at 15 Hz, the shell on the GPU), then this.

## Settings vs state

A **setting** is something the user chooses (glass on, which hacks rotate, toast timeout). It
lives in `shell.json`. **State** is where things are (pinned sidecar windows, launcher frecency,
dismissed alerts, last office workspace). It stays in `~/.local/state/astal-shell/`. The menu
shows settings only.

## The store — `lib/settings.ts`

- One typed schema: key → default. `setting(key)` returns a reactive state; setting it writes the
  file (debounced, `GLib.file_set_contents`, atomic).
- Unknown keys in the file are kept, missing keys read as the default, a malformed file is
  logged and read as all-defaults (never crashes the shell).
- A `Gio.FileMonitor` on the file: hand edits apply live, same as the menu's.
- `astal-shell set <key> <value>` / `astal-shell get <key>`: the same store from the CLI, so a
  keybind or a script never needs its own verb.

## The menu — `surfaces/Settings.tsx`

Sections, each a column of rows (label · control · one-line hint):

- **Backdrop**: startup mode (photo / random / a named ambient); rotation length (90 s);
  ambients on/off (the 12); hacks on/off — a filterable list of ~290 with a search box, all/none;
  hack draw scale (½ now); hacks at all (on/off); smooth rate (15 Hz).
- **Look**: theme; glass + its opacity (0.90); CRT (off/subtle/full); night temperature (4000 K)
  and whether it follows sunset.
- **Notifications**: toast timeout (6 s), max toasts (5), do-not-disturb (persisted).
- **Sound**: cava bars (24) and rate (30 fps).
- **Feel**: hover dwell/grace (500/350 ms), OSD hold (1.4 s), hot-edge dwell (400 ms).
- **Wallpaper**: rotation interval (5 min); directory shown read-only (nix owns it).

Poll periods and internal constants stay constants.

The hack list moves out of the nix `grep -vxE` into two layers: nix keeps excluding the hacks
that **cannot** work (they grab an empty screen); the menu's off-list is the user's taste.
`xss-host --list` stays the source of what exists.

## Jank pass — each its own commit

From the 2026-10-08 survey of the toggles:

1. **awake** shows on when logind refused the inhibitor (`awake.ts:36`): the toggle should
   reflect the fd, not the request.
2. **crt** resets to "off" on a shell restart while Hyprland keeps the shader on: read the live
   `decoration:screen_shader` at start, and persist it as a setting.
3. **night**: a manual toggle is lost at the next sunset/sunrise and on restart; "follow
   sunset" becomes a setting, a manual override is explicit.
4. **dnd** resets on restart: persist it.
5. **glass** shows on while a playing video has forced windows opaque: show the override.
6. **zen at startup** is hard-coded (`setBackdrop("zen")`): becomes the startup-mode setting.
7. The CLI usage string omits `quake`, `super`, `pop`; `lib/state.ts` is the keyboard poll, not
   state — rename to `lib/kbd.ts`.

## Status (2026-10-08)

Built: the store and `get`/`set`; the Settings surface with Backdrop (incl. the photo's interval),
Look, Notifications and Feel (incl. stay awake and the audio bars' rate); jank items 1, 2, 4, 5, 6
and 7. Item 3 is covered by `look.nightFollowsSun` (off, a manual toggle sticks); a manual toggle
with the schedule on still lasts until the next sunset or sunrise, as designed, and is not kept
across a restart. `backdrop.smoothHz`, `sound.vizBars` and the rail's Super+hover dwell
(`feel.hoverDwellMs`) are settings now, with a Settings row each; the hack draw scale was already
`backdrop.hackScale`. Open: the menu's clicks, typing and Super+Shift+click are unverified by hand.

## Slices

1. `lib/settings.ts` + `get`/`set` verbs + a test of load/merge/malformed (no UI).
2. Backdrop settings wired (startup mode, ambients, hacks, rotation, scale) — the ask that started
   this.
3. `Settings.tsx` with the Backdrop section, the keybind and the Aleph Super+Shift+click.
4. Look / Notifications / Sound / Feel sections, each moving its constant behind a setting.
5. Jank pass items 1–7, one commit each.

Verify each with `mise shell:check`, and a live `shell:dev` pass with `mise shot:layer` for the
menu's look.

## Open

- Hack thumbnails (a still per hack in the list) would help pick taste, but cost a render of
  each; not in these slices.
