# home-manager: install the shell and, where asked, run it as a user unit for the session.
# Off by default: on the Arch box caelestia still owns the session and the shell is run by
# hand (shell:dev) until cutover; the VM turns autostart on.
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

    xdg.configFile."astal-shell/config.json" = lib.mkIf (cfg.location != null) {
      text = builtins.toJSON cfg.location;
    };

    systemd.user.services.astal-shell = lib.mkIf cfg.autostart {
      Unit = {
        Description = "astal shell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package}";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
