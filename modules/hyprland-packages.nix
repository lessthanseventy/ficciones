# Hyprland + hyprexpo from Hyprland's own overlay on Hyprland's own nixpkgs pin (its deps are
# cached against that gcc; ours links a newer libstdc++ and guiutils fails to link). The plugin
# is built in the same package set, so it loads into the exact binary it was compiled against.
# One set for both hosts: modules/os on NixOS, modules/arch on Arch.
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
    })
  ];
}
