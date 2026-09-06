# ivysaur → NixOS: the migration runbook

`nixosConfigurations.ivysaur` (modules/os/ivysaur.nix over modules/os/default.nix) is the laptop
described by this flake. It evaluates and builds on the Arch box today; nothing here has been
run against the real disk. This document is the exact sequence for the day it is, written so the
person running it (Andrew, or a future session) needs no other context.

The shape of the move: **keep the disk, keep the btrfs subvolumes, keep /home byte for byte;
replace what is in `@` (the Arch root) with a NixOS root.** Garuda's own snapshot history stays
reachable in `/.snapshots` until it is deliberately deleted.

## 0 · What the laptop is (captured 2026-09-05)

| thing | value |
|---|---|
| CPU / RAM | i7-13700H (20 threads) / 62 GiB |
| GPUs | Intel Iris Xe `0000:00:02.0` (primary, `card2` on Arch), NVIDIA RTX 4060 Max-Q `0000:01:00.0` (`card1`) |
| driver today | `nvidia-open` 610.57, EnvyControl hybrid (`nvidia-drm.modeset=1`, DynamicPowerManagement=0x02) |
| firmware | UEFI, Secure Boot off, GRUB |
| disk | `nvme0n1`: p1 300 MB vfat ESP `AF10-16B1` at `/boot/efi`; p2 884.8 GB btrfs `b0077b04-b5d9-4693-9043-b46b7b28f42f`; p3 68.7 GB swap `dbc5438c-46d0-41b5-9530-2f4e0e907ed8` (resume device) |
| subvolumes | `@` / · `@home` /home · `@root` /root · `@srv` /srv · `@cache` /var/cache · `@log` /var/log · `@tmp` /var/tmp · `/.snapshots` (snapper, root config) |
| mount opts | `noatime,compress=zstd:3,ssd,discard=async,space_cache=v2` |
| kernel cmdline extras | `pcie_aspm=force intel_pstate=passive mem_sleep_default=deep` (kept in `boot.kernelParams`) |
| hosts | `127.0.0.1 appcount.appr` + admin/application/residents/management/maintenance subdomains (`networking.extraHosts`) |
| tz / locale | America/Denver / en_US.UTF-8 |

Everything in that table is encoded in `modules/os/ivysaur.nix`. If the hardware changes, change
the file, not the runbook.

## 1 · Before touching anything

1. **Back up.** `/home` survives the procedure by design, but the procedure can be botched:
   - `sudo btrfs subvolume snapshot -r /home /.snapshots/pre-nixos-home` (instant, on-disk).
   - An **off-disk** copy of what cannot be regenerated: `~/.ssh`, `~/.gnupg`, `~/.config/rbw`,
     `~/.floorp`, `~/.local/share/keyrings`, `~/.claude`, `~/.pi`, `~/projects` (git remotes exist
     for most, but `ficciones` is ~750 commits ahead of origin — push first, or copy).
   - `pacman -Qqe > ~/arch-explicit-packages.txt` and `pacman -Qm > ~/arch-foreign-packages.txt`
     (the second list is already reviewed in §5, but keep the raw file).
   - `/etc` as a whole: `sudo tar czf ~/arch-etc.tgz /etc` — NetworkManager profiles
     (`/etc/NetworkManager/system-connections`, wifi passwords), `/etc/hosts`, `/etc/fstab`.
2. **Push the repo.** `git push` every branch that matters; the flake is the machine now.
3. **Build the closure on Arch, ahead of time**, so the install day is a copy, not a compile:
   ```
   nix build .#nixosConfigurations.ivysaur.config.system.build.toplevel -o .dev/ivysaur
   ```
   (this is also the gate: it has to succeed before step 3 below).
4. Read §5 and decide what to do about each "no twin" item. None blocks booting.

## 2 · Boot medium

The NixOS **minimal ISO** (x86_64), written to a USB stick. It has `nix`, `git`, `btrfs-progs`.
The laptop's wifi works from the ISO via `wpa_supplicant`/`iwctl`; a USB-C ethernet dock is
easier. The build in §1.3 means the install needs the network only for what is not in the
Arch box's nix store (see §3.4 for copying that store over).

## 3 · Install (the destructive part)

All of this from the ISO shell as root. **Nothing before step 3.5 destroys anything.**

1. Mount the existing layout under `/mnt`:
   ```
   D=/dev/disk/by-uuid/b0077b04-b5d9-4693-9043-b46b7b28f42f
   O=noatime,compress=zstd:3,ssd,discard=async,space_cache=v2
   mount -o $O,subvol=@      $D /mnt
   mkdir -p /mnt/{home,root,srv,var/cache,var/log,var/tmp,boot/efi}
   mount -o $O,subvol=@home  $D /mnt/home
   mount -o $O,subvol=@root  $D /mnt/root
   mount -o $O,subvol=@srv   $D /mnt/srv
   mount -o $O,subvol=@cache $D /mnt/var/cache
   mount -o $O,subvol=@log   $D /mnt/var/log
   mount -o $O,subvol=@tmp   $D /mnt/var/tmp
   mount /dev/disk/by-uuid/AF10-16B1 /mnt/boot/efi
   swapon /dev/disk/by-uuid/dbc5438c-46d0-41b5-9530-2f4e0e907ed8
   ```
2. Snapshot the Arch root **read-only** so it can be rolled back to (§4):
   ```
   mount -o subvolid=5 $D /mnt-top      # the btrfs top level
   btrfs subvolume snapshot -r /mnt-top/@ /mnt-top/@arch-2026-09
   ```
3. Get the flake onto the target. `/mnt/home/andrew/projects/ficciones` is already there
   (it is `@home`). `cd` into it.
4. Optional but recommended: copy the Arch box's nix store closure so nothing rebuilds.
   From Arch beforehand: `nix copy --to file:///home/andrew/nix-export .#nixosConfigurations.ivysaur.config.system.build.toplevel`;
   from the ISO: `nix copy --from file:///mnt/home/andrew/nix-export --no-check-sigs <the store path>`.
5. **Empty the Arch root.** Everything in `@` except the mountpoints goes:
   ```
   cd /mnt && for d in *; do case "$d" in home|root|srv|var|boot) ;; *) rm -rf -- "$d";; esac; done
   rm -rf /mnt/var/{lib,spool,opt,db,games,local,mail} 2>/dev/null; ls /mnt /mnt/var
   ```
   (`@cache`/`@log`/`@tmp` are separate subvolumes and can be wiped too: `rm -rf /mnt/var/cache/* /mnt/var/log/* /mnt/var/tmp/*`.)
   Also clear the ESP of Garuda's loader: `rm -rf /mnt/boot/efi/EFI/Garuda /mnt/boot/efi/EFI/garuda` — leave `EFI/Boot`.
6. Install:
   ```
   nixos-install --flake /mnt/home/andrew/projects/ficciones#ivysaur --no-root-passwd --root /mnt
   ```
   `nixos-install` writes GRUB to the ESP and the kernels into `/mnt/boot` (inside `@`).
7. Set passwords: `nixos-enter --root /mnt -- passwd andrew` (and `passwd` for root, or leave
   root locked — `wheelNeedsPassword = false` is already set).
8. `umount -R /mnt; reboot`.

## 4 · First boot and rollback

- GRUB → NixOS → greetd (tuigreet) → `uwsm start hyprland-uwsm.desktop`. Log in as andrew.
  The astal shell is a user unit and comes up with `graphical-session.target`.
- home-manager is a NixOS module here: `modules/desktop` was applied by `nixos-install`. The
  out-of-store symlinks (`~/.config/hypr/hyprland.lua` → the repo) resolve because `@home` is
  the same `/home`.
- If it does not boot: reboot, hold the firmware key, pick the USB again, mount as in §3.1, and
  either
  - fix `modules/os/ivysaur.nix` and re-run §3.6 (nothing else needs redoing), or
  - **roll back to Arch**: from the top level, `mv @ @nixos-failed && btrfs subvolume snapshot @arch-2026-09 @`
    (writable snapshot of the read-only one), restore Garuda's ESP entry with
    `grub-install` from an Arch ISO (or `efibootmgr` pointing at `EFI/Garuda/grubx64.efi`
    if you did not delete it — consider not deleting it until NixOS has booted once).
- Once NixOS has booted: `sudo btrfs subvolume delete /.snapshots/pre-nixos-home` when you are
  sure, and `@arch-2026-09` when you are very sure. Garuda's numbered `/.snapshots/N` are inside
  the old snapper layout and can be deleted the same way.

## 5 · What has no nixpkgs twin (from `pacman -Qm`, 169 foreign packages)

Groups, with the decision each needs. Anything not listed either has a twin that
`modules/os/ivysaur.nix` already installs, or is a `lib32-*`/compat library that steam-run and
`programs.steam` make irrelevant.

| Arch package(s) | status |
|---|---|
| `caelestia-cli`, `caelestia-shell-git`, `quickshell-git`, `qt6-m3shapes-git`, `anyrun-qalculate-git`, `bumblebee-status`, `i3blocks-contrib`, `xautolock` | **dead** — the astal shell replaced them; do not carry |
| `agent-deck`, `claude-squad`, `lazyagent-bin`, `lazybeads-git`, `beads-bin`, `herdr-bin`, `seance`, `sesh-bin`, `lazy*-bin` (actions/jira/journal/org/rss/sql/ssh/sys/tail/tailscale/docker-ng), `oxker-bin`, `gobang-bin`, `dblab-bin`, `sqlit`, `nb`, `runal`, `rvpk`, `vpkedit`, `mult-bin`, `whispering-bin`, `bookokrat-bin`, `cheznav`, `cliamp`, `sampler`, `sysz`, `systemd-manager-tui`, `smassh-bin`, `telegramtui`, `bombadillo`, `gowall`, `grabc` | **TODO, per tool**: Go/Rust single binaries — most build from source with `buildGoModule`/`rustPlatform` in a small overlay, or run as-is under `nix-ld` from `~/.local/bin`. `Super+Shift+Return` binds `agent-deck`; keep it in `~/.local/bin` until packaged |
| `affine-bin`, `chatbox-bin`, `claude-desktop-native`, `devdocs-desktop`, `easydocker-bin`, `limux-bin`, `pixelorama-bin`, `prince-bin`, `rustdesk`, `ripcord-arch-libs`, `watchman-bin` | Electron/AppImage-ish: `rustdesk`, `pixelorama`, `watchman` exist in nixpkgs (installed); the rest **TODO** — AppImages run via `appimage-run` |
| `floorp` (Arch repo, not AUR — but **not in nixpkgs**) | **decision**: `floorp-bin` via an overlay/flake (e.g. the `floorp` package in `nixpkgs` PRs, or `github:hayateroid/floorp`), or Firefox with the same `userChrome.css` — the theme generator writes into `~/.floorp/<profile>/chrome`, so the profile dir option would change |
| `wgtray`, `wireguard-tray` | **TODO** — not in nixpkgs; `hyprland.lua` autostarts `wgtray` (harmless when missing). NetworkManager's WireGuard support covers the function |
| `envycontrol`, `supergfxctl` | **dead** — `hardware.nvidia.prime.offload` is the hybrid mode, `nvidia-offload <cmd>` replaces `prime-run`/`steam-nvidia` |
| `catppuccin-gtk-theme-mocha`, `gtk-engine-murrine`, `qt5-styleplugins` | twin: `catppuccin-gtk` (variant mocha, accent yellow) + `kvantum`; installed |
| `emulationstation-themes`, `steam-native-runtime`, `flac1.3`, `glew1.10`, `lib32-*` | `programs.steam` + `enable32Bit` cover it; ES-DE **TODO** (`emulationstation-de` is not in nixpkgs; flatpak) |
| `nodejs-mjml`, `nodejs-neovim`, `python-*`, `ruby-xdg`, `pipxu` | language-package-manager installs; redo with `npm i -g` / `pipx` under nix-ld, or `mise` |
| `tmux-plugin-manager`, `tmux-resurrect`, `tmuxinator`, `neofetch-git`, `fortune-mod-*`, `pokemon-wallpapers`, `ttf-rubik-vf`, `openvpn-update-systemd-resolved`, `reiserfsprogs`, `pacmixer`, `powerstat`, `gnu-netcat`, `telegram-tdlib`, `xdg-utils-handlr`, `rofi-pass`, `yay-bin`, `paru` | tmux plugins are already in `programs.tmux` (flake); the rest are cheap twins or not wanted on NixOS |

### Arch-only assumptions still in the flake / dotfiles

- `modules/desktop/default.nix` probes `/usr/bin/hyprctl` and `/usr/bin/git` with `command -v`
  fallbacks — warnings on NixOS, not blockers (the store binaries are on PATH).
- `modules/desktop/hypr/scripts/launch_hyprland.sh` execs `/usr/bin/Hyprland` — unused on
  NixOS (uwsm starts Hyprland); delete after the move.
- `~/.local/bin/rotate-wallpaper` — **replaced** by `hypr/scripts/rotate-wallpaper.sh` (repo,
  caelestia-free). On Arch it still needs `pacman -S hyprpaper` (the nix hyprpaper hits the
  GL/GBM seam on a non-NixOS host); on NixOS `hyprpaper` is in `systemPackages`.
- `~/.zshrc`, `~/.config/starship.toml`, `~/.config/nvim` are **not** flake-managed. `.zshrc`
  sources `~/.config/fzf/theme.zsh`, which the palette generator now writes; the rest survive
  untouched in `@home`.
- `mise` toolchains (erlang/elixir/node under `~/.local/share/mise`) are dynamic binaries built
  for glibc — `programs.nix-ld` with `stdenv.cc.cc`, `zlib`, `openssl`, `ncurses` covers them;
  if `mix` fails to start on first boot, `ldd $(mise which erl)` names the missing library to
  add to `programs.nix-ld.libraries`.
- The `pi` bun binary (flake.nix) — nix-ld as well; the flake's note is resolved by this.
- `AQ_DRM_DEVICES` in `hosts/ivysaur.{lua,conf}` now uses `/dev/dri/by-path/...` names because
  Arch numbers simpledrm as `card0` and NixOS will not. Verified to resolve on Arch (card2/card1);
  **verify at the next Hyprland start** that aquamarine accepts the symlinked paths (it `open()`s
  them, so it should).
- `hyprlock`: the generated `~/.config/hypr/hyprlock.conf` has not been exercised (locking the
  screen while this was written unattended was not an option). Try `hyprlock` once by hand.
- Qt: the Arch box never had `qt6ct`/`kvantum`, so `modules/desktop` defaults to Qt's `gtk3`
  platform theme (reads our GTK colours). `ivysaur.nix` sets `qt6ct` and installs it + kvantum.

## 6 · Open decisions (Andrew)

1. Floorp: nixpkgs has none. Overlay a `floorp` package, or move to Firefox + the same CSS?
2. Kernel: `linuxPackages` (LTS-ish default) vs `linuxPackages_latest`/zen. The Arch box runs
   plain `linux` today; the default is the safe first boot.
3. Delete `EFI/Garuda` from the ESP before or after the first successful NixOS boot (§3.5 vs §4).
4. Which of the §5 "TODO, per tool" binaries are actually used weekly — package those first.
