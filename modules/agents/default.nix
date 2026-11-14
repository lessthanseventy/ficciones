# The agent wiring as one home-manager module: tlon's service and slices, the agenix secrets,
# Claude Code's rules, skills, mods and shell, and the git config. Needs agenix's home-manager
# module beside it; the user and state version are the importer's.
{
  config,
  lib,
  pkgs,
  repo,
  tlonRepo,
  dbx,
  agentBrowser,
  agentDesktop,
  agenixPackage,
  pgIsReady,
  ...
}:
let
  # server' self-contained release, built in tlon's `.release` checkout at its release
  # pointer (tlon's `release:cut` task moves it; a merge to main deploys nothing). The
  # service below runs it headless; `server:console`/`:restart` drive the same
  # bin/server, so node + cookie agree via the release's own env.sh.
  serverRel = "${tlonRepo}/.release/server/_build/prod/rel/server";
  # Claude Code's hooks telling arena, by a pane option, what the Claude in the pane is doing;
  # a session outside tmux has no TMUX_PANE and sets nothing.
  arenaState = state: {
    hooks = [
      {
        type = "command";
        command =
          "[ -z \"$TMUX_PANE\" ] || tmux "
          + (
            if state == null then
              "set -pu -t \"$TMUX_PANE\" @arena_claude"
            else
              "set -p -t \"$TMUX_PANE\" @arena_claude ${state}"
          );
      }
    ];
  };
  arenaHooks = pkgs.writeText "arena-hooks.json" (
    builtins.toJSON {
      UserPromptSubmit = [ (arenaState "working") ];
      PostToolUse = [ (arenaState "working") ];
      Stop = [ (arenaState "done") ];
      Notification = [
        ((arenaState "waiting") // { matcher = "permission_prompt|elicitation_dialog"; })
      ];
      SessionEnd = [ (arenaState null) ];
    }
  );
in
{
  # rbw — Bitwarden CLI with an unlock agent, for interactive password management.
  # Config here is non-secret/declarative; master password + vault stay with Bitwarden.
  # Machine secrets (OLLAMA_API_KEY) use agenix, not rbw — rbw needs an interactive unlock,
  # wrong for a non-interactive spawn.
  programs.rbw = {
    enable = true;
    settings = {
      email = "andrew@lessthanseventy.com";
      # base_url = "https://vault.example.tld";  # ← self-hosted Vaultwarden goes here
      # pinentry-qt: rbw-agent has no controlling tty, so terminal pinentries EOF; a GUI
      # dialog sidesteps that. qt not gnome3 — this box is Hyprland/Qt, and gnome3 needs
      # GNOME's gcr-prompter.
      pinentry = pkgs.pinentry-qt;
      lock_timeout = 3600;
    };
  };

  # watchexec backs scripts/watch.sh's change-triggered test runner. LSP servers for
  # tlon's adapters/lsp (hover/definition/references/diagnostics as agent tools) — all
  # flake-managed so the next box gets them (Expert, the Elixir one, comes with
  # modules/menard-host.nix). The adapter registry in tlon's adapters/lspd/src/adapters.ts
  # spawns these by name — adding a language is an adapter object + usually a package here.
  home.packages = [
    dbx
    pkgs.watchexec
    pkgs.worktrunk
    agentBrowser
    agentDesktop
    pkgs.typescript-language-server
    pkgs.bash-language-server
    pkgs.vscode-json-languageserver
    pkgs.marksman
    pkgs.taplo
    pkgs.yaml-language-server
    # zls's minor version tracks the Zig that mise installs for arena
    pkgs.zls
    pkgs.actionlint
    pkgs.gdtoolkit_4
    pkgs.ruff
    pkgs.ast-grep
    # markdown lint, for agents
    pkgs.markdownlint-cli2
    # `agenix -e secrets/<name>.age` to create/edit a secret; decryption at switch is
    # handled by the agenix module (age.secrets below).
    agenixPackage

    # `tlon` — the product launcher: the office TUI, a thin wrapper over its mise task.
    (pkgs.writeShellScriptBin "tlon" ''
      cd ${tlonRepo} || { echo "tlon: repo not found at ${tlonRepo}" >&2; exit 1; }
      exec mise --cd ${tlonRepo} run office:run -- "$@"
    '')
  ];

  # age-encrypted secrets, decrypted at home:switch to $XDG_RUNTIME_DIR/agenix/<name>.
  # Gated on pathExists so the flake evaluates before the first secret is created.
  age.secrets =
    lib.optionalAttrs (builtins.pathExists ../../secrets/ollama-api-key.age) {
      ollama-api-key.file = ../../secrets/ollama-api-key.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/dbx-connections.age) {
      dbx-connections.file = ../../secrets/dbx-connections.age;
    };

  # The four working rules (modules/agents/how-to-work.md), as Claude Code's global CLAUDE.md.
  home.file.".claude/CLAUDE.md".source = ./how-to-work.md;
  home.file.".claude/skills/agent-desktop/SKILL.md".source = ./skills/agent-desktop/SKILL.md;
  home.file.".claude/skills/agent-browser/SKILL.md".source = ./skills/agent-browser/SKILL.md;
  xdg.configFile."worktrunk/config.toml".source = ./worktrunk.toml;
  # Claude Code's shells read these (settings.json: env.ZDOTDIR = ~/.claude/zsh): the user's
  # .zshenv and .zprofile, then a lean rc in place of ~/.zshrc's ~14k-line snapshot
  home.file.".claude/zsh/.zshenv".source = ./zsh/zshenv;
  home.file.".claude/zsh/.zprofile".source = ./zsh/zprofile;
  home.file.".claude/zsh/.zshrc".source = ./zsh/zshrc;
  # ...and the env they need, merged into settings.json (Claude Code rewrites that file, so
  # it stays mutable): ZDOTDIR above, and nothing that waits on a human; the shell snapshot
  # keeps only PATH, so these cannot live in the rc. No EDITOR: Claude Code's ctrl+g uses it.
  # autoCompactWindow: a 1M-window session otherwise grows to ~1M before compacting, and every
  # call re-reads all of it (one week-long session was 40% of a week's tokens at 455k a call).
  # 433k, as Claude Code compacts 33k short of the figure: at 400k.
  # CLAUDE_CODE_PLUGIN_DIRS: the mods (the changes pane, which /changes and /diff open, among them),
  # each by its store path, since the plugin loader refuses a module reached through a home.file symlink.
  # cc-plugin-diff off: where it is available it docks a Diff tab that takes over from that pane.
  # diffSidebarOpen off, in ~/.claude.json: the app's own diff panel opens on an edit otherwise,
  # and while it shows the dock gets no columns, so that pane has nowhere to draw.
  # The arena hooks replace any earlier copy of themselves and leave every other hook be.
  home.activation.claudeShellEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.claude/settings.json"
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile arena ${arenaHooks} '.env += {
           ZDOTDIR: (env.HOME + "/.claude/zsh"),
           GIT_EDITOR: "true", PAGER: "cat", GIT_PAGER: "cat", MANPAGER: "cat",
           GIT_TERMINAL_PROMPT: "0" }
         | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
             | map(select(. != "" and (endswith("-changes-pane") or endswith("-review-pane") or endswith("-transcript-rows") | not)))
               + ["${./mods/changes-pane}", "${./mods/review-pane}", "${./mods/transcript-rows}"] | join(":"))
         | .autoCompactWindow = 433000
         | .enabledPlugins["cc-plugin-diff@builtin"] = false
         | .hooks = reduce ($arena[0] | to_entries[]) as $e (.hooks // {};
             .[$e.key] = [(.[$e.key] // [])[] | select(tostring | contains("@arena_claude") | not)] + $e.value)' "$cfg" > "$tmp"; then
        run chmod 600 "$tmp"
        run mv -f "$tmp" "$cfg"
      else
        rm -f "$tmp"
      fi
    fi
    state="$HOME/.claude.json"
    if [ -f "$state" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq '.diffSidebarOpen = false' "$state" > "$tmp"; then
        run chmod 600 "$tmp"
        run mv -f "$tmp" "$state"
      else
        rm -f "$tmp"
      fi
    fi
  '';

  # the interactive shell's rc: ls and cat are eza and bat at a terminal, the plain tools
  # for anything that reads their output (an agent's Bash)
  home.file.".zshrc".source = ../os/zshrc;
  # git's global ignore (~/.gitconfig's core.excludesFile): the sandboxes' phantom files too
  home.file.".gitignore".source = ../os/gitignore;
  # the workflow every repo here keeps (linear history: rebase, fast-forward, stacks); git
  # reads this beside ~/.gitconfig, which stays the machine's (identity, credentials)
  home.file.".config/git/config".source = ../os/gitconfig;
  # out of the store: `mise use -g` and `mise trust` write this file
  home.file.".config/mise/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${repo}/modules/os/mise.toml";

  # The node cookie the service and its remote shells share (rel/env.sh.eex reads it into
  # RELEASE_COOKIE; `server:console`, `server:dev` and tlon-cli.sh rpc use it): written once, 0600, never
  # rotated by a switch — a rotation would cut a running remote shell off its node.
  home.activation.tlonCookie = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    f="$HOME/.local/share/tlon/cookie"
    if [ ! -s "$f" ]; then
      run mkdir -p "$(dirname "$f")"
      run sh -c "umask 077; head -c 32 /dev/urandom | base64 | tr -d '/+=\n' > \"$f\""
    fi
  '';

  # The always-up sovereign channel as a headless systemd --user service. A
  # self-contained release (tlon's `server:release` task) means ExecStart is one
  # absolute path with no toolchain on PATH. ExecStartPre migrates first —
  # server never serves on a schema it can't repair. LOOPBACK-only. The store is
  # Postgres `tlon` on the local socket (one-brain piece C, 2026-09-18; the SQLite
  # corpus at ~/.local/share/funes/wb.db was copied in once with
  # `mix server.import_sqlite`). Node name + cookie come from the release's own env.sh, so
  # `server:console`/`:restart` reach THIS node. Build the release before the first
  # `home:switch` that starts it.
  # The machine seed tlon's Server.Seed applies on every boot: this box's workspaces and
  # the facts its coworkers must see (tlon's own repo holds only product knowledge).
  xdg.configFile."tlon/seed.exs".source = ./tlon-seed.exs;

  # The office's CPU yields to the desktop: CPU is split between cgroups before
  # processes, so each coworker scope in app.slice was a full peer of the video player.
  # tlon.service, its coworkers' tmux scopes and its redeploys all run here (tlon passes
  # --slice=tlon.slice); the quota keeps 6 of 20 threads (and the fans) free regardless.
  # keep-old on both: restarting a slice stops every scope in it, so a changed weight
  # would end each coworker pane and Claude session at home:switch.
  systemd.user.slices = {
    tlon = {
      Unit.Description = "tlon — the office's coworkers, server and rebuilds";
      Unit.X-SwitchMethod = "keep-old";
      Slice = {
        CPUWeight = 20;
        IOWeight = 20;
        CPUQuota = "1400%";
      };
    };

    # Claude sessions started by hand (the `claude` function in modules/os/zshrc) and the
    # suites they run; apart from tlon.slice so `server:stop` never takes them down.
    # At the default weight, and no quota: the session's own UI is typed into from
    # inside this cgroup, and a low share made it wait behind every suite in the slice.
    agents = {
      Unit.Description = "agents — Claude sessions started from a terminal";
      Unit.X-SwitchMethod = "keep-old";
      Slice = {
        CPUWeight = 100;
        IOWeight = 100;
      };
    };
  };

  systemd.user.services.tlon = {
    Unit = {
      Description = "tlon — the always-up sovereign MCP channel (loopback)";
      Documentation = [ "file://${tlonRepo}/server/AGENTS.md" ];
      After = [ "network.target" ];
    };
    Service = {
      Type = "exec";
      Slice = "tlon.slice";
      # Worklines: artifact checks run git in the repo checkout; the memory pass is
      # on for the always-up node (the Maintain sweeps ride Oban's cron; both post/park,
      # never act).
      # The switchboard runs here too — delivery bookkeeping only until an arbiter
      # exists.
      Environment = [
        # The service shells tmux/claude (both profile-owned) — a boot-time start
        # inherits the manager's PATH before the session imports the profile, and the
        # staffing pass died on `tmux: enoent` for 31 h.
        "PATH=${config.home.profileDirectory}/bin:/usr/local/bin:/usr/bin:/bin"
        "TLON_DATABASE=tlon"
        # one-brain D + E: the web UI on loopback :4042 (tailscale-only beyond the box) and
        # Oban on the store (the cron drain; the sweeps follow)
        "TLON_START_WEB=1"
        "TLON_WEB_PORT=4042"
        "TLON_START_OBAN=1"
        "TLON_START_MCP=1"
        "TLON_START_SWITCHBOARD=1"
        "TLON_START_ATTENTION=1"
        "TLON_MCP_PORT=4040"
        "TLON_WORKLINE_ROOT=${repo}"
        "TLON_MEMORY_PASS=1"
        # the office's small talk, on the cheap ollama tier, only while an office watches
        "TLON_BANTER=1"
      ];
      # Seed + repair run at app boot (Server.Bootstrap); only the schema migration
      # is a pre-step.
      # A --user unit cannot order itself After= the system postgresql.service, so at
      # boot it can start before the socket accepts; wait (up to 60 s) instead of
      # failing the migration and leaning on Restart.
      ExecStartPre = [
        "/bin/sh -c 'for i in $(seq 60); do ${pgIsReady} -q -h /run/postgresql && exit 0; sleep 1; done; exit 1'"
        "${serverRel}/bin/server eval Server.Release.migrate()"
      ];
      ExecStart = "${serverRel}/bin/server start";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
