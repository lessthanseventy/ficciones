# babylon (~/projects/babylon, which arena's plugin hands every session): the sessions' tickets over
# MCP on loopback :4050. babylon writes and starts its own user service (systemd unit on Linux,
# launchd agent on the Mac) with `babylon install`; activation runs it, so the unit is babylon's one
# definition. It rewrites the unit on every switch and enables --now, which leaves a running
# service running.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  arenaRepo = "${home}/projects/arena";
  babylonBin = "${home}/projects/babylon/bin/babylon";
in
{
  home.packages = [
    # `babylon` — the tickets from a shell, the checkout's own script; it reads the repo you are in
    (pkgs.writeShellScriptBin "babylon" ''
      export PATH=${
        lib.makeBinPath [
          pkgs.curl
          pkgs.jq
        ]
      }:$PATH
      exec ${babylonBin} "$@"
    '')
  ]
  # the Linux desktop links arena into ~/.local/bin, which the Mac's PATH lacks
  ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin (
    pkgs.writeShellScriptBin "arena" ''exec ${arenaRepo}/zig-out/bin/arena "$@"''
  );

  # After reloadSystemd, which stops a unit the new generation no longer links: install then starts
  # babylon again, and never leaves it stopped by that step.
  # install puts the PATH it finds (tmux, git, mise, claude, jq, curl) into the service, so the
  # profile's bin leads; coreutils is there for the Mac's `timeout`, which it only needs there.
  home.activation.babylonService = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -x ${babylonBin} ]; then
      PATH=${config.home.profileDirectory}/bin:${lib.makeBinPath [ pkgs.coreutils ]}:$PATH \
        run ${babylonBin} install
    fi
  '';

  # install owns babylon.service, so what this machine adds to it is a drop-in beside it.
  # tlon's gate skips the house's checks where godot is missing; here that is a failure.
  xdg.configFile."systemd/user/babylon.service.d/house-gate.conf" =
    lib.mkIf pkgs.stdenv.hostPlatform.isLinux
      {
        text = ''
          [Service]
          Environment=TLON_HOUSE_GATE=required
        '';
      };
}
