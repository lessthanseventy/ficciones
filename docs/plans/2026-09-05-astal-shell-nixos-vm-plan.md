# Astal shell in a NixOS VM — the road off Arch

Companion to `2026-09-02-astal-shell-design.md`. That document designs the shell. This one says
where it runs while it is being built, and how the same code becomes the laptop's OS.

The ask: build the shell inside this repo, test it in a VM until it is right, then replace Garuda
with NixOS on the laptop. Both halves want the same thing — a machine described entirely by this
flake — so the VM is not a test rig that gets thrown away; it is the laptop's configuration booted
under QEMU.

---

## 1 · Two layers, one tree

```
modules/desktop/            home-manager: the user's desktop (runs on Arch today, NixOS later)
  default.nix               hypr symlinks + host.conf selection + imports ./shell
  hypr/                     hyprland.conf, hypridle.conf, scripts/
  hypr/hosts/ivysaur.conf   monitors + AQ_DRM_DEVICES for the laptop
  hypr/hosts/vm.conf        one virtio monitor, one card
  shell/                    the astal shell — source + package + systemd user unit
modules/os/                 NixOS: the operating system underneath
  default.nix               the common profile: user, Hyprland, greetd, pipewire, fonts, home-manager
  vm.nix                    QEMU specifics: virtio-gpu GL, the repo shared in at its real path
```

`modules/desktop` is kept home-manager-shaped on purpose. It applies on the Arch box through
`home:switch` exactly as before, and `modules/os` consumes it as a home-manager-in-NixOS module.
The laptop migration adds `modules/os/ivysaur.nix` (nvidia PRIME, btrfs, the real hardware) next
to `vm.nix` and nothing above it changes.

## 2 · The repo rides into the VM at its real path

Every out-of-store symlink in this flake points at `/home/andrew/projects/ficciones`. Rather than
fight that, the VM mounts the host working tree at the same path over virtiofs/9p. Consequences:

- `hyprctl reload` and the shell's `ags run` see the same files the editor on the host sees.
  The dev loop is identical inside and outside the VM.
- The VM has no copy of the repo to drift.
- The mount is writable, so `ags types` and friends can be run from either side.

## 3 · What differs per host lives in `host.conf`

`hyprland.conf` gained one line, `source = ~/.config/hypr/host.conf`, and lost the monitor and
GPU-device lines that only make sense on the laptop. home-manager links `host.conf` to
`hypr/hosts/<host>.conf`, where `<host>` is the `ficciones.desktop.host` option — `ivysaur` on
Arch, `vm` in the VM. A missing `AQ_DRM_DEVICES` or a monitor name that does not exist is the
difference between Hyprland starting and Hyprland dying in a VM.

## 4 · The shell package

`modules/desktop/shell/package.nix` builds the shell with `ags bundle` (AGS 3.x, `Aylur/ags`
flake input; astal follows it). The home-manager module installs the binary and a
`astal-shell.service` user unit bound to `graphical-session.target`, gated on
`ficciones.desktop.shell.autostart`. The VM turns that on. On Arch it stays off — caelestia still
owns the session there, and the shell is run by hand with `shell:dev` until cutover.

## 5 · Dev loop

| task            | does                                                         |
|-----------------|--------------------------------------------------------------|
| `vm:build`      | build the VM runner from `nixosConfigurations.vm`            |
| `vm:run`        | boot it (KVM, virtio-gpu GL, repo shared in)                 |
| `shell:dev`     | run the shell from source with `ags run`                     |
| `shell:check`   | `ags types` + `tsc --noEmit`                                 |
| `shell:restart` | restart the user unit                                        |
| `shell:logs`    | follow the unit's journal                                    |

## 5a · Two bars, two axes (2026-09-05)

The shape of the machine is *vertical workspaces, horizontal scrolling strips*. So there are two
bars, one per axis, not one rail:

- **Left rail** — the vertical axis: workspaces stacked, the minimap (`▯▮▯▯` + `2/4`, which
  column of the strip you occupy), power at the foot.
- **Top bar** — the horizontal axis: focused window title at the left, clock centred, status as
  text at the right (`NET ▮▮▮▯ ssid · VOL ▮▮▯▯ · BAT 87%⚡`), tray to come.

The rotated vertical title from design §4 is gone; a title reads better along the top.

**Detail on demand.** Each status item in the bar is the headline; the control panel for it
(wifi list, bluetooth devices, sink switcher, brightness, power profile — design §5) opens
anchored to that item. Click and `Super+B` are the sure things; hover-to-expand the way
caelestia does it is wanted and will be tried once the panels exist — with a short dwell so a
pointer crossing the bar on the way somewhere else does not pop a panel.

## 5b · One palette, every surface (2026-09-05)

The shell's ink is amber on black, with green and pink as highlights and the active thing in
inverse video (amber field, black text). That is not a shell rule, it is the machine's rule:
Console.Style, ghostty, floorp, GTK apps, Hyprland borders, hyprlock — anything reasonably
themeable follows the same palette, so nothing on screen looks like a guest.

Doing that by hand-mirroring hex values into five files is how the shell and the cockpit
already drifted (green body vs amber body). The fix is a single source of truth and generators:

```
modules/desktop/theme/palette.nix     the one list of semantic colours + the font
  → shell/style/_tokens.scss          (generated at build; the checked-in file becomes output)
  → console/lib/console/style.ex      (Console.Style reads the same names)
  → ~/.config/ghostty/theme           (palette 0-15 + fg/bg/cursor/selection = inverse)
  → GTK 3/4 CSS (@define-color)        (Adwaita colours overridden, ComicShanns as gtk-font-name)
  → floorp userChrome.css / userContent (chrome + about: pages; sites stay themselves)
  → hyprland.conf general:col.*        (already amber; source the generated file)
  → Qt: qt6ct colour scheme + kvantum  (hyprland.conf already sets QT_QPA_PLATFORMTHEME=qt6ct)
  → btop theme, and whatever else      (mine ~/.config on ivysaur for every app with a theme
                                        file — lazygit, bat, fzf, cava, hyprlock — and add a
                                        generator per hit; that survey is the phase's first task)
```

Console.Style moves to the amber body too; green there becomes the "live" highlight as in the
shell. This is its own phase, after the drawer, so the palette settles on real surfaces first.

## 5c · What landed 2026-09-05 (afternoon)

- **Rail** (64px): WS pane listing only this monitor's workspaces (wheel switches them), the
  stacked clock (click = drawer), weather glyph + °F under it, SYS pane at the foot (wifi and
  bluetooth items with popover panes, StatusNotifier tray), power. The COL minimap is gone —
  the window row on the bar already says where you are.
- **Bar**: this monitor's workspace windows in strip order at the left (focused = class +
  title, others = app icons, click focuses); CPU · RAM · GPU · NET cells pinned right, each
  icon · KEY · number · 8-glyph braille sparkline, coloured green/amber/red by load, click
  opens the drawer on PERF; VOL (slider, mute) and BAT (watts, ETA, power profiles) popovers.
- **Drawer**: DASH (headlines + calendar), PERF (full history), MEDIA (mpris transport),
  WEATHER, AGENTS (tlon-cli shell-status). 1-5 / Tab / Esc. `Super+Shift+I`, the clock, the
  weather item, `astal-shell toggle drawer`, `astal-shell show drawer perf`.
- **Dropped**: the text cat (glyph art at 12px does not read). If a running cat comes back it
  is sprite frames paced by CPU, not text.
- **Gotchas**: pane padding lives on `.panel-body` (GtkOverlay); glib-networking or no TLS;
  private-use glyphs go in source as `\u{...}`; never inject keys with ydotool while testing —
  keycode 1 is Escape and a stuck modifier follows.

## 5d · Evening 2026-09-05 — cutover and the rest of the surfaces

caelestia is gone from hyprland.conf; swaync masked (it D-Bus-activated into the gap). Landed:
notifications (toasts + the right-hand hub with history and toggles, hot edge, Super+N),
launcher and clipboard (anyrun and fuzzel retired), keybind cheatsheet (Super+Shift+/), CRT
shaders (Super+Shift+C, hub), the zen backdrop (per monitor, lorenz/life/boids/rule 30 in
colour, Super+Shift+Z), glass (window opacity, Super+Shift+T), night light on the sunset
schedule, a brightness slider that is the backlight alone and hyprsunset gamma when the
external monitor (no DDC/CI through the dock) is plugged in. astal is a top-level flake input.

## 5e · Night of 2026-09-05 — one palette, Lua, ivysaur

- **§5b landed.** `modules/desktop/theme/palette.nix` is the single source (hues, roles, ANSI
  slots, the font); `render.nix` is one pure function per surface; `default.nix` is the
  home-manager module that writes them. Surfaces: shell `_palette.scss` + `lib/palette.ts`
  (checked in, generated — `mise theme:gen` writes them, `checks.palette-sync` fails the flake
  on drift, the shell package rewrites them before bundling), `Console.Palette` + Console.Style
  on the amber body (green = live), ghostty theme+config, kitty, wezterm, GTK 3/4 (@define-color
  + font + selection), qt6ct/qt5ct colours+qss, kvantum, btop, floorp userChrome/userContent
  (vendored, the `:root` block generated), hyprland `theme.lua`/`theme.conf`, hyprlock,
  lazygit, bat (`--theme=ansi`), fzf, cava, tmux (spliced into flake.nix). Vendored templates
  carry `@placeholders@` where they carried hex. Verified by screenshot: btop, lazygit,
  nautilus, pavucontrol-qt, the bar. Not verified: floorp (needs a restart), hyprlock, the
  cockpit live (865 tests green).
- **Found and fixed:** `~/.local/bin/rotate-wallpaper` still called `caelestia wallpaper` every
  five minutes and caelestia's scheme applier rewrote gtk.css/cava/btop behind the generators.
  Replaced by `hypr/scripts/rotate-wallpaper.sh` (hyprpaper on every monitor; on Arch hyprpaper
  must come from pacman — the nix one dies on GBM). Qt was never themed on this box: no
  qt6ct/kvantum installed; `theme.qtPlatformTheme` defaults to Qt's `gtk3` theme here and
  `ivysaur.nix` sets `qt6ct`.
- **hyprland.lua.** 1:1 port, `hosts/<host>.lua`, `theme.lua` dofile'd. `scripts/hypr-lua-check.sh`
  runs the file in a nested Hyprland (`FICCIONES_HYPRDIR`, `FICCIONES_HYPR_NO_AUTOSTART`) and
  diffs binds/options/workspace rules/animations against the live instance: identical. A
  running Hyprland stays pinned to the config path it started with, so **the .conf files stay
  linked until the next Hyprland start** (which prefers `.lua`, per the log). The VM boots the
  Lua config with the shell unit active.
- **ivysaur.** `modules/os/ivysaur.nix` + `nixosConfigurations.ivysaur` (btrfs layout by UUID,
  GRUB on the 300 MB ESP, nvidia-open + PRIME offload, snapper on /home, steam+gamemode,
  nix-ld, tailscale, greetd/tuigreet). Runbook: `2026-09-05-ivysaur-nixos-migration-runbook.md`.
- **Bar:** window cells icon-snug (6px), hover opens the popover, click focuses, no tooltip,
  no wrap on the rail wheel, `cursor:no_warps`.

## 6 · Phase status

Design §7 phases, with where this plan lands them:

1–6. **Done** (§5c, §5d). OSDs dropped on purpose (Andrew: not wanted).
§5b one palette — **done** (§5e). hyprland.lua — **done, transition pending a Hyprland
restart** (then delete hyprland.conf, hosts/*.conf, the three TRANSITION lines in
modules/desktop/default.nix and theme.conf in theme/default.nix). ivysaur — **config built,
install pending Andrew** (§7, the runbook).
Next: the pinned "sidecar" window (pin = float + left edge + reserved area on every workspace);
hover-to-open for the other bar cells; agents card → dossier.

## 7 · Laptop migration checklist

Written up in full in `docs/plans/2026-09-05-ivysaur-nixos-migration-runbook.md`: the hardware
table, backups, the exact install commands (keep the disk and subvolumes, replace `@`), the
rollback (`@arch-2026-09` read-only snapshot), the `pacman -Qm` review (dead / twin / TODO per
tool), the Arch-only assumptions left in the flake, and the open decisions (floorp, kernel,
when to delete Garuda's ESP entry, which TUI binaries to package first).

- [x] `modules/os/ivysaur.nix`: nvidia-open + PRIME offload, steam, gamemode, btrfs by UUID,
      snapper for `/home` only.
- [x] `programs.nix-ld` (pi's bun binary and mise's toolchains).
- [x] `pacman -Qm` enumerated (runbook §5).
- [x] Arch-only assumptions listed (runbook §5); `/usr/bin` probes stay as warnings.
- [ ] Andrew: the open decisions, then the runbook.
