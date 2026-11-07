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
  # pacman's xdg-desktop-portal stays installed (flatpak and gtk4 need it); these, linked by the
  # same names, are what runs. The document portal still mounts through Arch's setuid fusermount3.
  frontend = pkgs.xdg-desktop-portal;
  gtkPortal = pkgs.xdg-desktop-portal-gtk;
  share = pkg: rel: { source = "${pkg}/share/${rel}"; };
in
{
  home = {
    packages = [
      pkgsHypr.hyprland
      pkgsHypr.hypridle
      pkgsHypr.hyprsunset
      portal
    ];
    file = {
      ".local/share/ficciones/graphics-drivers".source = graphicsDrivers;
      # hyprland.lua loads these at start; NixOS has them at /etc/hypr/plugins
      ".local/share/hypr/plugins/hyprexpo.so".source =
        "${pkgsHypr.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so";
      ".local/share/hypr/plugins/hyprwindowshade.so".source =
        "${pkgsHypr.hyprwindowshade}/lib/HyprWindowShade.so";
    };
  };

  # dbus and systemd look in these user dirs before /usr, and neither reads the nix profile
  xdg.dataFile = {
    "xdg-desktop-portal/portals/hyprland.portal" =
      share portal "xdg-desktop-portal/portals/hyprland.portal";
    "xdg-desktop-portal/portals/gtk.portal" = share gtkPortal "xdg-desktop-portal/portals/gtk.portal";
    "dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service" =
      share portal "dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service";
    "dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service" =
      share gtkPortal "dbus-1/services/org.freedesktop.impl.portal.desktop.gtk.service";
    "dbus-1/services/org.freedesktop.portal.Desktop.service" =
      share frontend "dbus-1/services/org.freedesktop.portal.Desktop.service";
    "dbus-1/services/org.freedesktop.portal.Documents.service" =
      share frontend "dbus-1/services/org.freedesktop.portal.Documents.service";
    "dbus-1/services/org.freedesktop.impl.portal.PermissionStore.service" =
      share frontend "dbus-1/services/org.freedesktop.impl.portal.PermissionStore.service";
    "dbus-1/services/org.hyprland.hyprpolkitagent.service" =
      share pkgsHypr.hyprpolkitagent "dbus-1/services/org.hyprland.hyprpolkitagent.service";
  };
  xdg.configFile = {
    # Hyprland starts it, and it brings up graphical-session.target: the shell, the portals
    "systemd/user/hyprland-session.target" =
      share pkgsHypr.hyprland "systemd/user/hyprland-session.target";
    "systemd/user/xdg-desktop-portal.service" =
      share frontend "systemd/user/xdg-desktop-portal.service";
    "systemd/user/xdg-desktop-portal-rewrite-launchers.service" =
      share frontend "systemd/user/xdg-desktop-portal-rewrite-launchers.service";
    "systemd/user/xdg-document-portal.service" =
      share frontend "systemd/user/xdg-document-portal.service";
    "systemd/user/xdg-permission-store.service" =
      share frontend "systemd/user/xdg-permission-store.service";
    "systemd/user/xdg-desktop-portal-gtk.service" =
      share gtkPortal "systemd/user/xdg-desktop-portal-gtk.service";
    "systemd/user/xdg-desktop-portal-hyprland.service" =
      share portal "systemd/user/xdg-desktop-portal-hyprland.service";
    "systemd/user/hyprpolkitagent.service" =
      share pkgsHypr.hyprpolkitagent "systemd/user/hyprpolkitagent.service";
  };
}
