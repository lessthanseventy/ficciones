# The operating system under the desktop: one user, Hyprland, sound, network, fonts, and
# home-manager applying modules/desktop for that user. Hardware-free on purpose — vm.nix and
# (later) ivysaur.nix add the machine. See docs/plans/2026-09-05-astal-shell-nixos-vm-plan.md.
{
  config,
  pkgs,
  lib,
  repo,
  astalShell,
  ...
}:

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
  };
  # hyprland.lua's autostart expects these on PATH; hyprlock/hypridle are never replaced
  # by the shell (design §7), ghostty is $TERMINAL there.
  environment.systemPackages = with pkgs; [
    ghostty
    hypridle
    hyprlock
    hyprpaper
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
