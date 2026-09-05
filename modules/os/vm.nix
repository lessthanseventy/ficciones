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

  # No greeter: the VM exists to look at the shell, not to log in. The session is uwsm's
  # (see programs.hyprland.withUWSM in default.nix); start-hyprland alone leaves
  # graphical-session.target dead and the shell unit never runs.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${lib.getExe pkgs.uwsm} start -- hyprland-uwsm.desktop";
      user = "andrew";
    };
  };
  users.users.andrew.initialPassword = "andrew";

  # The way in from the host: `mise vm:ssh` (password andrew, port 2222). Guest journals and
  # hyprctl without the serial-console dance.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  home-manager.users.andrew.ficciones.desktop.host = "vm";

  virtualisation.vmVariant.virtualisation = {
    memorySize = 6144;
    cores = 4;
    diskSize = 8192;
    forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
    sharedDirectories.ficciones = {
      source = repo;
      target = repo;
    };
    # Plain virtio-vga, no virgl: Hyprland and GTK4 run fine on llvmpipe at this size, and
    # the store QEMU's GL display (gtk or sdl, gl=on) aborts on the Arch host — nix libepoxy
    # cannot find the host EGL without a nixGL wrapper. Revisit on NixOS, where it just works.
    qemu.options = [
      "-vga none"
      "-device virtio-vga"
      "-display gtk,show-cursor=on"
    ];
  };
}
