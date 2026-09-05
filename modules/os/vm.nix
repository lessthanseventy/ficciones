# The QEMU guest. Boots straight into Hyprland as andrew, with the working tree mounted at
# its real path so every out-of-store symlink in the flake resolves and the dev loop (edit on
# the host, `hyprctl reload` / `ags run` in the guest) is the same one as on a live desktop.
#
# Build: mise vm:build   Run: mise vm:run
{
  config,
  pkgs,
  lib,
  repo,
  ...
}:

{
  networking.hostName = "vm";

  # No greeter: the VM exists to look at the shell, not to log in.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${lib.getExe config.programs.hyprland.package}";
      user = "andrew";
    };
  };
  users.users.andrew.initialPassword = "andrew";

  home-manager.users.andrew.ficciones.desktop.host = "vm";

  virtualisation.vmVariant.virtualisation = {
    memorySize = 6144;
    cores = 4;
    diskSize = 8192;
    sharedDirectories.ficciones = {
      source = repo;
      target = repo;
    };
    # virtio-gpu with virgl so Hyprland gets a GL renderer instead of dying on llvmpipe probing.
    qemu.options = [
      "-vga none"
      "-device virtio-vga-gl"
      "-display gtk,gl=on,show-cursor=on"
    ];
  };
}
