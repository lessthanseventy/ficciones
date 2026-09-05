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

## 6 · Phase status

Design §7 phases, with where this plan lands them:

1. Scaffold, style system, the two bars — **this plan**. Rail: workspaces, minimap, power.
   Bar: title, clock, status as text. The rule-30 strip and tray are the next commits.
2. Drawer + panes — next.
3–6. As designed.

## 7 · Laptop migration checklist (deferred, tracked here)

- `modules/os/ivysaur.nix`: `hardware.nvidia` + PRIME offload, `programs.steam`, gamemode,
  btrfs subvolumes + snapper for `/home` only (generations cover `/`).
- `programs.nix-ld` for the pi bun binary (see the note in `flake.nix`).
- Everything from the AUR that has no nixpkgs twin — enumerate with `pacman -Qm` first.
- The `personalbox` home configuration's Arch-only assumptions (`/usr/bin/hyprctl` probes) —
  each already falls back on `command -v`, so they are warnings, not blockers.
