# Hyprland + hyprexpo from Hyprland's own overlay on Hyprland's own nixpkgs pin (its deps are
# cached against that gcc; ours links a newer libstdc++ and guiutils fails to link). The plugin
# is built in the same package set, so it loads into the exact binary it was compiled against.

{ system, hyprexpo }:
let
  hyprland = hyprexpo.inputs.hyprland;
in
import hyprland.inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    hyprland.overlays.hyprland-packages
    hyprexpo.overlays.default
    (final: prev: {
      # each patch's header says why it exists
      hyprland = prev.hyprland.overrideAttrs (o: {
        patches = (o.patches or [ ]) ++ [
          ./os/patches/hyprland-aquamarine-honours-disable_logs.patch
          ./os/patches/hyprland-focus-arms-border-loop.patch
        ];
      });
      # per-window shaders; here, the close burn (hyprland.lua). Pinned by hand: a bump is a
      # rebuild against this exact Hyprland, checked before it loads into the live session.
      hyprwindowshade = final.hyprlandPlugins.mkHyprlandPlugin {
        pluginName = "hyprwindowshade";
        version = "0-unstable-2026-11-04";
        src = final.fetchFromGitHub {
          owner = "ManofJELLO";
          repo = "HyprWindowShade";
          rev = "9cd398103d2d52dad549ee6d5a768d0046c220dd";
          hash = "sha256-3m5079S6vRgORU6wzIh9HWkGQ17JnocX/MfsGDMVkFI=";
        };
        installPhase = "install -Dm755 HyprWindowShade.so $out/lib/HyprWindowShade.so";
        meta.license = final.lib.licenses.mit;
      };
    })
  ];
}
