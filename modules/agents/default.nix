# The agent wiring as one home-manager module: the agent slice, the agenix secrets,
# Claude Code's rules, skills, mods and shell, and the git config. Needs agenix's home-manager
# module beside it; the user and state version are the importer's.
{
  config,
  lib,
  pkgs,
  dbx,
  agentBrowser,
  agentDesktop,
  agenixPackage,
  ...
}:
let
  asterionSeed = pkgs.writeShellScript "asterion-seed" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.jq
        pkgs.coreutils
      ]
    }:$PATH
    ${builtins.readFile ./asterion-seed.sh}
  '';
in
{
  imports = [
    ./claude.nix
    ./babylon.nix
  ];

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

  # watchexec backs scripts/watch.sh's change-triggered test runner. The language servers are
  # what Claude Code's LSP tool (hover/definition/references/diagnostics) spawns by name, all
  # flake-managed so the next box gets them (Expert, the Elixir one, comes with
  # modules/menard-host.nix).
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

    # the `claude` function in modules/os/zshrc sets it as CLAUDE_CODE_SHELL_PREFIX
    (pkgs.writeShellScriptBin "agent-work" (builtins.readFile ./agent-work.sh))

    # `asterion` — the house window, the built app; `asterion dev` runs it from source,
    # `asterion widget` the small always-on-top one, `asterion demo` the made-up one with no server.
    (pkgs.writeShellScriptBin "asterion" ''
      ASTERION_SEED=${asterionSeed}
      ASTERION_REPO=${config.home.homeDirectory}/projects/asterion
      ${builtins.readFile ./asterion.sh}
    '')
    (pkgs.writeShellScriptBin "house" ''exec asterion "$@"'')

  ];

  # Asterion's calendar feed and own bot token, seeded from the secrets below into its user://
  # (create-if-absent). Also run by `asterion`: at a switch the secrets may not be decrypted yet.
  home.activation.asterionSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${asterionSeed}
  '';

  # age-encrypted secrets, decrypted at home:switch to $XDG_RUNTIME_DIR/agenix/<name>.
  # Gated on pathExists so the flake evaluates before the first secret is created.
  age.secrets =
    lib.optionalAttrs (builtins.pathExists ../../secrets/ollama-api-key.age) {
      ollama-api-key.file = ../../secrets/ollama-api-key.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/asterion-telegram-token.age) {
      asterion-telegram-token.file = ../../secrets/asterion-telegram-token.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/dbx-connections.age) {
      dbx-connections.file = ../../secrets/dbx-connections.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/calendar-work.age) {
      calendar-work.file = ../../secrets/calendar-work.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/plaid-client-id.age) {
      plaid-client-id.file = ../../secrets/plaid-client-id.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/plaid-secret.age) {
      plaid-secret.file = ../../secrets/plaid-secret.age;
    }
    // lib.optionalAttrs (builtins.pathExists ../../secrets/plaid-access-token.age) {
      plaid-access-token.file = ../../secrets/plaid-access-token.age;
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
  # ...by ZDOTDIR, merged into settings.json (Claude Code rewrites that file, so it stays mutable)
  # beside the env every machine's shells get (./claude.nix).
  # autoCompactWindow: a 1M-window session otherwise grows to ~1M before compacting, and every
  # call re-reads all of it (one week-long session was 40% of a week's tokens at 455k a call).
  # 433k, as Claude Code compacts 33k short of the figure: at 400k.
  # CLAUDE_CODE_PLUGIN_DIRS: the mods (the changes pane, which /changes and /diff open, among them),
  # each by its store path, since the plugin loader refuses a module reached through a home.file symlink.
  # CLAUDE_CODE_FORCE_TERMINAL_IMAGES: under tmux the inline-image mod draws nothing without it.
  # cc-plugin-diff off: where it is available it docks a Diff tab that takes over from that pane.
  # diffSidebarOpen off, in ~/.claude.json: the app's own diff panel opens on an edit otherwise,
  # and while it shows the dock gets no columns, so that pane has nowhere to draw.
  home.activation.claudeShellEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.claude/settings.json"
    # a machine Claude Code has not run on yet has no file, and would get none of this
    [ -f "$cfg" ] || { run mkdir -p "$HOME/.claude"; run sh -c 'echo "{}" > "$1"' _ "$cfg"; }
    for mod in ${./mods/changes-pane} ${./mods/review-pane} ${./mods/transcript-rows} ${./mods/inline-image}; do
      PATH=/usr/bin:/nix/var/nix/profiles/default/bin:$PATH sh ${./plugin-snapshot.sh} root "mod-$(basename "$mod")" "$mod" || true
    done
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq '.env.ZDOTDIR = (env.HOME + "/.claude/zsh")
         | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
             | map(select(. != "" and (endswith("-changes-pane") or endswith("-review-pane") or endswith("-transcript-rows") or endswith("-inline-image") or endswith("-next-step") | not)))
               + ["${./mods/changes-pane}", "${./mods/review-pane}", "${./mods/transcript-rows}", "${./mods/inline-image}"] | join(":"))
         | .env.CLAUDE_CODE_FORCE_TERMINAL_IMAGES = "1"
         | .autoCompactWindow = 433000
         | .enabledPlugins["cc-plugin-diff@builtin"] = false' "$cfg" > "$tmp"; then
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
  # read-only, so `mise use -g` refuses: a global tool is added in modules/os/mise.toml
  home.file.".config/mise/config.toml".source = ../os/mise.toml;

  systemd.user.slices = {
    # Claude sessions started by hand (the `claude` function in modules/os/zshrc) and the
    # suites they run, in one cgroup. At the default weight, and no quota: the session's own UI is typed into from
    # inside this cgroup, and a low share made it wait behind every suite in the slice.
    # The suites keep off the desktop by core instead (agent-work.sh pins them to the
    # E-cores): no weight or quota helped, as all-core load drags every core's clock down.
    agents = {
      Unit.Description = "agents — Claude sessions started from a terminal";
      Unit.X-SwitchMethod = "keep-old";
      Slice = {
        CPUWeight = 100;
        IOWeight = 100;
      };
    };
  };

  systemd.user.services.sandbox-sweep = {
    Unit.Description = "remove the placeholders a killed Claude sandbox leaves under ~/projects and babylon's work root";
    Service = {
      Type = "oneshot";
      ExecStart = "${
        pkgs.writeShellScript "sandbox-sweep" (
          "PATH=${
            lib.makeBinPath [
              pkgs.findutils
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.git
            ]
          }\n"
          + builtins.readFile ./sandbox-sweep.sh
        )
      } %h/projects %h/.cache/babylon/work";
    };
  };
  systemd.user.timers.sandbox-sweep = {
    Unit.Description = "sweep stale Claude sandbox placeholders every ten minutes";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
