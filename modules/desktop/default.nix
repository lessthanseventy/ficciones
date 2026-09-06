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
  repo,
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

    # sudo's askpass (scripts/sudo-askpass): random glyphs per keystroke; a tty or a dialog
    # when stdin is not a terminal (hyprpm and friends used to hang on it).
    home.file.".local/bin/sudo-askpass" = { source = ./scripts/sudo-askpass; executable = true; };
    home.sessionVariables.SUDO_ASKPASS = "${config.home.homeDirectory}/.local/bin/sudo-askpass";

    xdg.configFile = {
      "hypr/hyprland.lua" = linkTo "hyprland.lua";
      # TRANSITION (2026-09-05): a running Hyprland stays pinned to the config path it started
      # with, so the .conf (and its host/theme includes) stay linked until the next Hyprland
      # start picks hyprland.lua. Delete these three lines + hyprland.conf + hosts/*.conf then.
      "hypr/hyprland.conf" = linkTo "hyprland.conf";
      "hypr/host.conf" = linkTo "hosts/${cfg.host}.conf";
      "hypr/hypridle.conf" = linkTo "hypridle.conf";
      "hypr/host.lua" = linkTo "hosts/${cfg.host}.lua";

      "hypr/scripts/launch_hyprland.sh" = linkTo "scripts/launch_hyprland.sh";
      "hypr/scripts/quake-toggle.sh" = linkTo "scripts/quake-toggle.sh";
      "hypr/scripts/shot-region.sh" = linkTo "scripts/shot-region.sh";
      "hypr/scripts/shell-req.sh" = linkTo "scripts/shell-req.sh";

      # CRT screen shaders, switched by path (hyprctl keyword decoration:screen_shader …).
      "hypr/shaders/crt-full.glsl" = linkTo "shaders/crt-full.glsl";
      "hypr/shaders/crt-subtle.glsl" = linkTo "shaders/crt-subtle.glsl";
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
    # hyprland.conf goes down home-manager's slow path, which is `mv` to the backup and THEN
    # `ln` — a window with no file, which is all Hyprland needs to fall back to defaults.
    home.activation.hyprlandReload = lib.hm.dag.entryAfter [ "linkGeneration" ] reloadHyprland;
  };
}
