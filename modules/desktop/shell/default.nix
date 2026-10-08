# home-manager: install the shell and run it as a user unit for the session.
# `shell:dev` runs it from source instead.
{
  config,
  lib,
  pkgs,
  astalShell,
  ...
}:

let
  cfg = config.ficciones.desktop.shell;
in
{
  options.ficciones.desktop.shell = {
    package = lib.mkOption {
      type = lib.types.package;
      default = astalShell;
      description = "The built shell (modules/desktop/shell/package.nix).";
    };
    autostart = lib.mkEnableOption "start the shell with graphical-session.target";
    wallpapers = lib.mkOption {
      type = lib.types.str;
      default = "~/Pictures/Wallpapers";
      description = "Directory of images the backdrop rotates through (the shell is the wallpaper daemon).";
    };
    location = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.float);
      default = null;
      example = { lat = 38.8; lon = -104.8; };
      description = "lat/lon for the weather pane (open-meteo). null = the pane says so.";
    };
  };

  config = {
    # The bundle plus the `ags` CLI it was built with, so `ags run` / `ags types` on a live
    # desktop use the same Astal libraries the package does.
    home.packages = [
      cfg.package
      cfg.package.passthru.ags
    ];

    xdg.configFile."astal-shell/config.json".text = builtins.toJSON (
      { wallpapers = cfg.wallpapers; } // (if cfg.location != null then cfg.location else { })
    );

    # A unit, so a crash restarts and lands in the journal — the shell's own log is in-memory only.
    # `on-failure`, not `always`: a gjs exception exits non-zero, an intentional quit stays quit.
    # The start limit is looser than systemd's 5-in-10s because a Hyprland restart yanks the
    # socket and the shell dies a few times before the display settles.
    systemd.user.services.astal-shell = lib.mkIf cfg.autostart {
      Unit = {
        Description = "astal shell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 10;
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package}";
        # Off NixOS the nix gtk finds no GPU driver and falls back to software (GskCairoRenderer):
        # point it at the nix mesa, as nixGL does, and GTK renders on the iGPU with Vulkan.
        Environment = [
          "__EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
          "GBM_BACKENDS_PATH=${pkgs.mesa}/lib/gbm"
          "LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri"
          "VK_DRIVER_FILES=${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json"
        ];
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
