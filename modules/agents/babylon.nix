# babylon (~/projects/babylon, which arena's plugin hands every session): the sessions' tickets over
# MCP on loopback :4050, as a systemd unit on Linux and a launchd agent on the Mac. Each runs the
# release babylon's own release task builds, which makes and migrates its SQLite file as it starts.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
  arenaRepo = "${home}/projects/arena";
  rel = "${home}/.local/share/babylon/rel/bin/babylon";
  # tmux (profile-owned) is how it learns which panes run Claude; coreutils gives its pipeline
  # `timeout`, which the Mac lacks; git, mise and claude run the gate and the review
  path = "${
    lib.makeBinPath [ pkgs.coreutils ]
  }:${config.home.profileDirectory}/bin:/usr/local/bin:/usr/bin:/bin";
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
      exec ${home}/projects/babylon/bin/babylon "$@"
    '')
  ]
  # the Linux desktop links arena into ~/.local/bin, which the Mac's PATH lacks
  ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin (
    pkgs.writeShellScriptBin "arena" ''exec ${arenaRepo}/zig-out/bin/arena "$@"''
  );

  systemd.user.services.babylon = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "babylon — the Claude sessions' tickets, over MCP (loopback)";
      After = [ "network.target" ];
      ConditionPathExists = rel;
    };
    Service = {
      Type = "exec";
      Environment = [
        "PATH=${path}"
        "BABYLON_SERVE=1"
        "BABYLON_PORT=4050"
      ];
      ExecStart = "${rel} start";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.babylon = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      # exits clean until the first release is built, so launchd does not respawn it
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "[ -x ${rel} ] || exit 0; exec ${rel} start"
      ];
      EnvironmentVariables = {
        HOME = home;
        PATH = path;
        BABYLON_SERVE = "1";
        BABYLON_PORT = "4050";
      };
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      StandardOutPath = "${home}/Library/Logs/babylon.log";
      StandardErrorPath = "${home}/Library/Logs/babylon.log";
    };
  };
}
