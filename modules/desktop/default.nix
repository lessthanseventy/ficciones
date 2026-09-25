# The Hyprland stack. home-manager places symlinks that point back at these files in the
# working tree, so `hyprctl reload` picks up an edit immediately — a keybind tweak must not
# cost a home:switch while this config is still being tuned. Same reasoning as the pi
# extension paths in flake.nix: the real file, not a store snapshot.
#
# The price of that: the live compositor reads a file GIT owns, so a checkout is a desktop
# change. A commit without this directory leaves ~/.config/hypr/hyprland.lua dangling, and
# Hyprland answers a missing config by loading built-in defaults — silently, no error. Hence
# the git hooks below, and hence this module belongs on every branch, not on a feature branch.
#
# Individual files, never the `hypr/` directory: leftovers (caelestia's scheme/, hyprpaper.conf)
# still sit there as real files, and linking the directory would push them into the tree.
{
  config,
  lib,
  pkgs,
  repo,
  tlonRepo,
  ...
}:

let
  cfg = config.ficciones.desktop;
  linkTo =
    rel:
    { source = config.lib.file.mkOutOfStoreSymlink "${repo}/modules/desktop/hypr/${rel}"; };

  # Shared by both activation entries: reload every live instance, no-op when none (a headless
  # switch, a VM build). hyprctl is the system's (pacman), so probe rather than name a store path.
  reloadHyprland = ''
    hyprctl="$(command -v hyprctl 2>/dev/null || echo /usr/bin/hyprctl)"
    if [ -x "$hyprctl" ]; then
      for inst in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
        [ -d "$inst" ] || continue
        run env HYPRLAND_INSTANCE_SIGNATURE="$(basename "$inst")" "$hyprctl" reload >/dev/null 2>&1 || true
      done
    fi
  '';
in
{
  imports = [ ./shell ./theme ];

  options.ficciones.desktop.host = lib.mkOption {
    type = lib.types.str;
    default = "ivysaur";
    description = ''
      Which hypr/hosts/<host>.lua becomes ~/.config/hypr/host.lua: the monitor layout,
      persistent workspaces and GPU device order that only make sense on one machine.
    '';
  };

  config = {
    # Home. The weather pane's open-meteo query.
    ficciones.desktop.shell.location = { lat = 38.7977014100912; lon = -104.80787634502575; };

    # mkDefault so modules/os can still state it outright for NixOS without a conflict.
    ficciones.desktop.shell.autostart = lib.mkDefault true;

    # sudo's askpass (scripts/sudo-askpass): random glyphs per keystroke; a tty or a dialog
    # when stdin is not a terminal (hyprpm and friends used to hang on it).
    # Claude Code skills tracked in tlon's adapters/skills; an out-of-store link so an edit lands
    # without a switch
    home.file.".claude/skills/drive-cockpit".source =
      config.lib.file.mkOutOfStoreSymlink "${tlonRepo}/adapters/skills/drive-cockpit";
    home.file.".local/bin/sudo-askpass" = { source = ./scripts/sudo-askpass; executable = true; };
    # recolours open ghostty surfaces to the live theme (the switch runs it; see lib/theme.ts)
    home.file.".local/bin/ficciones-recolor" = { source = ./scripts/ficciones-recolor; executable = true; };
    # a stream URL (m3u8/mpd) into mpv, referer and all — what The Stream Detector copies out of
    # a page whose own player lies to Mpris (Ctrl+Super+M plays the clipboard)
    home.file.".local/bin/mpv-stream" = { source = ./scripts/mpv-stream; executable = true; };
    programs.mpv = {
      enable = true;
      scripts = [ pkgs.mpvScripts.mpris ]; # real Mpris: the deck's transport and position work
      config = { gpu-context = "wayland"; hwdec = "auto-safe"; force-window = "yes"; keep-open = "yes"; ytdl = "yes"; osd-font = "ComicShannsMono Nerd Font"; };
    };
    home.sessionVariables.SUDO_ASKPASS = "${config.home.homeDirectory}/.local/bin/sudo-askpass";

    # piper voices (the nix piper-tts ships none; pacman's piper-voices-en-* was 1.8 GB of every
    # voice, none in use — `say` is kokoro via litellm). Two general ones, pinned from the
    # rhasspy/piper-voices release; add a voice = its two files + hashes (nix-prefetch-url):
    #   piper -m ~/.local/share/piper-voices/en_US-lessac-medium.onnx --output-raw < text | aplay
    home.file.".local/share/piper-voices" = {
      recursive = true;
      source = let
        base = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0";
        voice = path: name: hashes: [
          { name = "${name}.onnx"; path = pkgs.fetchurl { url = "${base}/${path}/${name}.onnx"; hash = builtins.elemAt hashes 0; }; }
          { name = "${name}.onnx.json"; path = pkgs.fetchurl { url = "${base}/${path}/${name}.onnx.json"; hash = builtins.elemAt hashes 1; }; }
        ];
      in pkgs.linkFarm "piper-voices" (
        voice "en/en_US/lessac/medium" "en_US-lessac-medium" [ "sha256-Xv4J5pkCGHgnr2RuGm6dJp3udp+Yd9F7FrG0buqvAZ8=" "sha256-7+GcQXvtBV8taZCCSMa6ZQ+hNbyGiw5quz2hgdq2kKA=" ]
        ++ voice "en/en_GB/alan/medium" "en_GB-alan-medium" [ "sha256-CjCWaJMiBedigB8e/Cc2zUsBIDKWIq32K+CeVjOdMzA=" "sha256-wPDRJOWJXADnwDs13MgofzGaaZijZbGC3rXI51LujB4=" ]
      );
    };

    home.packages = with pkgs; [
      # terminal file managers on trial as THE picker (a termfilechooser portal wraps one of them);
      # yazi was pacman's before, lf/vifm are new (2026-09-07)
      yazi lf vifm
      # user-level tools moved off pacman (2026-09-07 survey): the flake owns what the next box
      # needs; pacman keeps the kernel, drivers, Hyprland and its ecosystem until NixOS
      fastfetch fd lazygit jujutsu gh rclone tokei zenith lnav flyctl mise
      # pandoc from the binary cache — pacman's built it locally through ~190 haskell-* packages
      pandoc
      signal-desktop slack discord podman-desktop audacity strawberry
      # the theme module renders configs for these; the binaries were pacman's (survey 2026-09-07)
      starship bat cava btop kitty wezterm delta
      # decided in modules/os/ivysaur.nix, applied to today's profile too
      libreoffice-stable qbittorrent pavucontrol eza imv hyprpicker brightnessctl diff-so-fancy
      # dev / cli
      direnv difftastic tealdeer ugrep procs duf dust ncdu yt-dlp graphviz cloudflared sshfs strace wtype wev pamixer bluetui
      # asterion (neovim) system deps: nvim-treesitter main compiles parsers with the CLI; conform formats lua/sh
      tree-sitter stylua shfmt
      lazydocker lazysql lazyjj lazyjournal lazyssh
      # the agent CLIs and their tooling, off pacman (survey 2026-09-07); ollama stays pacman's
      # ollama-cuda (the GPU build), plocate pacman's (its updatedb timer is a system unit)
      claude-code codex uv libation piper-tts
      # screenshots: flameshot is Super+Shift+S only (hypr/scripts/shot-region.sh); the card is grim (shell/lib/capture.ts)
      flameshot
      # the clipboard history behind the rail's clipboard card and Super+V (hyprland.lua's
      # wl-paste --watch at start); pacman's went in the 2026-09-07 sweep as a dependency
      cliphist wl-clipboard
      # hypr/scripts/quake-toggle.sh reads hyprctl's json through jq: pacman's went as an orphan
      # in the 2026-09-08 sweep and F12 spawned a terminal per press (2026-09-08)
      jq
      # more of the 2026-09-08 sweep's collateral: grim + slurp came off as hyprshot's deps (the
      # shell's thumbnails, capture card and `mise shot:*` are grim); zoxide/sesh/cliamp were
      # tmux's dependents; aplay/amixer for the terminal
      grim slurp zoxide sesh cliamp alsa-utils
      # pi-sandbox's Linux deps (bubblewrap + socat): socat went in the same sweep and pi
      # "glitched like crazy" without it (2026-09-08 evening); bwrap is pacman's today, owned here too
      socat bubblewrap
      # the last pacman-only user tools (survey 2026-09-08); yq-go is what pacman called go-yq
      ripgrep fzf atuin yq-go sqlite
    ];

    xdg.configFile = {
      # portals: hyprland for screencast/screenshot, gtk for the rest — including the file
      # chooser (GTK 3, so it takes the theme + gtk.css like every other GTK window). Was a
      # hand-written file naming kde for FileChooser, the one Qt/KDE piece on the desktop.
      "xdg-desktop-portal/hyprland-portals.conf".text = ''
        [preferred]
        default = hyprland;gtk
        org.freedesktop.impl.portal.FileChooser = gtk
      '';
      # no BLE MIDI: wireplumber's bluez5 monitor registers a GATT MIDI application every
      # start and bluez refuses it (journal noise at every login, 2026-09-07)
      "wireplumber/wireplumber.conf.d/50-no-bluez-midi.conf".text = ''
        monitor.bluez.properties = {
          bluez5.midi = false
        }
      '';
      "hypr/hyprland.lua" = linkTo "hyprland.lua";
      "hypr/hypridle.conf" = linkTo "hypridle.conf";
      "hypr/host.lua" = linkTo "hosts/${cfg.host}.lua";

      "hypr/scripts/launch_hyprland.sh" = linkTo "scripts/launch_hyprland.sh";
      "hypr/scripts/quake-toggle.sh" = linkTo "scripts/quake-toggle.sh";
      "hypr/scripts/shot-region.sh" = linkTo "scripts/shot-region.sh";
      "hypr/scripts/shell-req.sh" = linkTo "scripts/shell-req.sh";

      # CRT screen shaders, switched by path (hyprctl keyword decoration:screen_shader …).
      "hypr/shaders/crt-full.glsl" = linkTo "shaders/crt-full.glsl";
      "hypr/shaders/crt-subtle.glsl" = linkTo "shaders/crt-subtle.glsl";

      # Neovim = asterion, a SIBLING repo (master plan 2026-09-17 §3): the whole config dir as one
      # out-of-store link, so an edit there is live and lazy.nvim owns plugins (lazy-lock.json in
      # that repo). Nix owns only nvim's system deps (below) and the rendered palette file. The
      # December config (claudevim) was moved to ~/projects/claudevim as a quarry.
      "nvim" = { source = config.lib.file.mkOutOfStoreSymlink "${builtins.dirOf repo}/asterion"; };
    };

    # scripts/git-hooks/ holds the hooks (post-checkout/-merge/-rewrite, all one script), so they
    # are versioned rather than sitting untracked in .git/hooks — which core.hooksPath then stops
    # git from reading at all. Only the samples live there, so nothing is lost.
    # git is probed, not pulled from pkgs: it is a hard prerequisite for having this repo at all,
    # and a store git would add ~50MB of closure (perl included) for one `config` call.
    home.activation.hyprlandGitHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      gitBin="$(command -v git 2>/dev/null || echo /usr/bin/git)"
      if [ -e "${repo}/.git" ] && [ -x "$gitBin" ]; then
        run "$gitBin" -C "${repo}" config --local core.hooksPath "${repo}/scripts/git-hooks"
      fi
    '';

    # linkGeneration's batched `ln -sfn` is atomic, so a steady-state switch does not disturb a
    # running compositor. The first switch on a fresh box does: taking over an existing real
    # hyprland.lua goes down home-manager's slow path, which is `mv` to the backup and THEN
    # `ln` — a window with no file, which is all Hyprland needs to fall back to defaults.
    home.activation.hyprlandReload = lib.hm.dag.entryAfter [ "linkGeneration" ] reloadHyprland;

    # The keyring the PAM stack unlocks at login is `login`; with no default pointer, the first
    # libsecret client asks for the default collection, gets a "create a keyring" prompt, and
    # gnome-keyring 50 falls over after it (2026-09-07: Default_keyring appeared, then a
    # segfault). The pointer is gnome-keyring's own file, so it is only ever filled in, never
    # overwritten.
    home.activation.keyringDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      d="${config.xdg.dataHome}/keyrings"
      if [ -f "$d/login.keyring" ] && [ ! -s "$d/default" ]; then
        run sh -c 'printf login > "$1"' _ "$d/default"
      fi
    '';
  };
}
