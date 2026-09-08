# The operating system under the desktop: one user, Hyprland, sound, network, fonts, and
# home-manager applying modules/desktop for that user. Hardware-free on purpose — vm.nix and
# (later) ivysaur.nix add the machine. See docs/plans/2026-09-05-astal-shell-nixos-vm-plan.md.
{
  config,
  pkgs,
  lib,
  repo,
  astalShell,
  hyprexpo,
  pi,
  ...
}:

let
  # Hyprland + hyprexpo from Hyprland's own overlay on Hyprland's own nixpkgs pin (its deps
  # are cached against that gcc; ours links a newer libstdc++ and guiutils fails to link),
  # with glaze held at 7.x: Hyprland 0.56.2's CMake wants `glaze 7...<8`, that nixpkgs has 8,
  # so the stock flake package falls to a FetchContent git clone the sandbox cannot do. The
  # plugin is built in the same package set, so it loads into the exact binary it was compiled
  # against.
  hyprland = hyprexpo.inputs.hyprland;
  pkgsHypr = import hyprland.inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
    overlays = [
      hyprland.overlays.hyprland-packages
      hyprexpo.overlays.default
      (final: prev: {
        # aquamarine's log connection honours debug:disable_logs (patches/…; upstream 0.56.2 writes
        # every libinput debounce line to hyprland.log regardless — 2026-09-07)
        hyprland = prev.hyprland.overrideAttrs (o: {
          patches = (o.patches or [ ]) ++ [ ./patches/hyprland-aquamarine-honours-disable_logs.patch ];
        });
        glaze-hyprland = (prev.glaze.override { enableSSL = false; enableInterop = false; }).overrideAttrs (_: rec {
          version = "7.2.0";
          src = prev.fetchFromGitHub {
            owner = "stephenberry";
            repo = "glaze";
            tag = "v${version}";
            hash = "sha256-f3NVRi3SXKo42hn0WCw7JsOK3EkdOVJIcuzhPorKjFY=";
          };
        });
      })
    ];
  };
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  users.users.andrew = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" "video" "audio" "input" "networkmanager" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # withUWSM: Hyprland no longer starts a systemd session target itself, and the shell's unit
  # binds to graphical-session.target. uwsm owns the session (env export, the target, teardown)
  # once hyprland.lua runs `uwsm finalize`.
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
    # the Hyprland hyprexpo was built against — a plugin loads into that binary only
    package = pkgsHypr.hyprland;
    portalPackage = pkgsHypr.xdg-desktop-portal-hyprland;
  };
  # the gtk portal answers what hyprland's does not: Settings (the color-scheme GTK 4 reads)
  # and the FileChooser modules/desktop names in hyprland-portals.conf
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  # the plugin at a fixed path; hyprland.lua loads it at start when the file exists (on Arch
  # hyprpm owns loading, and the path is absent)
  environment.etc."hypr/plugins/hyprexpo.so".source =
    "${pkgsHypr.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so";
  # hyprland.lua's autostart expects these on PATH; hyprlock/hypridle are never replaced
  # by the shell (design §7), ghostty is $TERMINAL there. No hyprpaper: the shell's backdrop
  # is the wallpaper.
  environment.systemPackages = with pkgs; [
    pi # the agent harness — the bun binary nix-ld loads (below)
    ghostty
    hypridle
    hyprlock
    hyprsunset
    hyprpolkitagent
    cliphist
    wl-clipboard
    libqalculate
    fd
    jq
    git
    vim
  ];

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  security.polkit.enable = true;

  # One font, everywhere (Andrew's rule): ComicShannsMono Nerd Font as THE monospace, and the
  # sans/serif slots too so nothing on the desktop falls back to a proportional face.
  fonts = {
    packages = [ pkgs.nerd-fonts.comic-shanns-mono ];
    fontconfig.defaultFonts = {
      monospace = [ "ComicShannsMono Nerd Font Mono" ];
      sansSerif = [ "ComicShannsMono Nerd Font" ];
      serif = [ "ComicShannsMono Nerd Font" ];
    };
  };

  # ---- the pi bun binary + mise-installed toolchains -----------------------------------------
  # A `bun build --compile` ELF must not be patchelf'd (flake.nix); nix-ld gives it a loader
  # without touching its bytes. The same loader serves mise's erlang/elixir/node downloads,
  # which are plain dynamic binaries. pi is on the system path above so the VM proves the loader.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [ stdenv.cc.cc zlib openssl ncurses libxcrypt-legacy ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit repo astalShell; };
    users.andrew = {
      imports = [ ../desktop ];
      home.stateVersion = "25.11";
      ficciones.desktop.shell.autostart = true;
    };
  };

  system.stateVersion = "25.11";
}
