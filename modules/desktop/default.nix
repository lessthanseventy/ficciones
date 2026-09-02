# The Hyprland stack. home-manager places symlinks that point back at these files in the
# working tree, so `hyprctl reload` picks up an edit immediately — a keybind tweak must not
# cost a home:switch while this config is still being tuned. Same reasoning as the pi
# extension paths in flake.nix: the real file, not a store snapshot.
#
# Individual files, never the `hypr/` directory: caelestia writes ~/.config/hypr/scheme/ and
# rotate-wallpaper rewrites hyprpaper.conf at runtime, so both stay unmanaged real files —
# linking them would push runtime churn into the working tree.
{ config, repo, ... }:

let
  linkTo =
    rel:
    { source = config.lib.file.mkOutOfStoreSymlink "${repo}/modules/desktop/hypr/${rel}"; };
in
{
  xdg.configFile = {
    "hypr/hyprland.conf" = linkTo "hyprland.conf";
    "hypr/hypridle.conf" = linkTo "hypridle.conf";

    "hypr/scripts/launch_hyprland.sh" = linkTo "scripts/launch_hyprland.sh";
    "hypr/scripts/quake-toggle.sh" = linkTo "scripts/quake-toggle.sh";
    "hypr/scripts/shot-region.sh" = linkTo "scripts/shot-region.sh";
  };
}
