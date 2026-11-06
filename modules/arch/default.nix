# What modules/os gives a NixOS host, for home-manager on the Arch base. Arch keeps what has to
# match the kernel or run as root: kernel, nvidia, its own mesa, ly, PAM — so hyprlock stays
# pacman's (a nix hyprlock cannot run the setuid unix_chkpwd, and never unlocks). Hyprland and
# the rest of its stack come from here. `mise run hyprland:install` does the root half once.
{
  pkgs,
  hyprexpo,
  ...
}:

let
  pkgsHypr = import ../hyprland-packages.nix {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit hyprexpo;
  };
  # nixpkgs' GL finds its drivers under /run/opengl-driver, as on NixOS; hyprland:install points
  # that at this link. Env vars (nix-gpu's way) would not do: Hyprland hands its env to every
  # app it launches, and a pacman app would load nix's mesa.
  graphicsDrivers = pkgs.buildEnv {
    name = "graphics-drivers";
    paths = [
      pkgsHypr.mesa
      pkgsHypr.intel-media-driver
    ];
  };
  portal = pkgsHypr.xdg-desktop-portal-hyprland;
in
{
  home = {
    packages = [
      pkgsHypr.hyprland
      pkgsHypr.hypridle
      pkgsHypr.hyprsunset
      portal
    ];
    file.".local/share/ficciones/graphics-drivers".source = graphicsDrivers;
    # hyprland.lua loads it at start; NixOS has it at /etc/hypr/plugins
    file.".local/share/hypr/plugins/hyprexpo.so".source =
      "${pkgsHypr.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so";
  };

  # dbus and systemd look in these user dirs before /usr, and neither reads the nix profile
  xdg.dataFile = {
    "xdg-desktop-portal/portals/hyprland.portal".source =
      "${portal}/share/xdg-desktop-portal/portals/hyprland.portal";
    "dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service".source =
      "${portal}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service";
    "dbus-1/services/org.hyprland.hyprpolkitagent.service".source =
      "${pkgsHypr.hyprpolkitagent}/share/dbus-1/services/org.hyprland.hyprpolkitagent.service";
  };
  xdg.configFile = {
    "systemd/user/xdg-desktop-portal-hyprland.service".source =
      "${portal}/share/systemd/user/xdg-desktop-portal-hyprland.service";
    "systemd/user/hyprpolkitagent.service".source =
      "${pkgsHypr.hyprpolkitagent}/share/systemd/user/hyprpolkitagent.service";
  };
}
