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
  # Repos whose landings wait on their local main for `babylon push`; every other repo pushes on landing.
  offerRepos = "arena:ficciones:menard";
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
  # arena, in the profile's bin: a Claude session's PATH has that and not ~/.local/bin. It runs the
  # binary arena's install task puts outside any checkout (babylon builds a landing in a tree of
  # its own), and the checkout's build only on a machine where no install has run.
  ++ [
    (pkgs.writeShellScriptBin "arena" ''
      bin="''${XDG_DATA_HOME:-$HOME/.local/share}/arena/bin/arena"
      [ -x "$bin" ] || bin=${arenaRepo}/zig-out/bin/arena
      exec "$bin" "$@"
    '')
  ];

  # After reloadSystemd, which stops a unit the new generation no longer links: install then starts
  # babylon again, and never leaves it stopped by that step.
  # install puts the PATH it finds (tmux, git, mise, claude, jq, curl) into the service, so the
  # profile's bin leads; coreutils is there for the Mac's `timeout`, which it only needs there.
  home.activation.babylonService = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -x ${babylonBin} ]; then
      if out=$(BABYLON_OFFER=${offerRepos} \
        PATH=${config.home.profileDirectory}/bin:${lib.makeBinPath [ pkgs.coreutils ]}:$PATH \
        run ${babylonBin} install 2>&1); then
        printf '%s\n' "$out"
      else
        printf 'babylon: install failed: %s\n' "$(printf '%s\n' "$out" | tail -n 1)" >&2
      fi
    fi
  '';
}
