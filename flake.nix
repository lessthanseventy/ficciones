{
  description = "ficciones — one person's whole computer as modules, each a Borges story. funes is the first.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # agenix — age-encrypted secrets committed to this repo, decrypted at home:switch by the box's
    # ssh key (no runtime unlock). This is the right tool for MACHINE secrets a non-interactive
    # process needs (OLLAMA_API_KEY for the Tlön pi spawn / funes); rbw stays for interactive
    # passwords. See secrets/secrets.nix + the age.secrets block below.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager, agenix }:
    let
      # One system for now; this box is x86_64-linux. Widen when a second arch appears.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # pi (github.com/earendil-works/pi) — the agent harness manos plugs into. It is NOT a
      # build toolchain (those are erlang/elixir/bun in mise); it is a program the human
      # runs, so Nix owns it and it lives in the home profile. pi ships no nixpkgs package
      # and no flake, so we wrap its prebuilt, bun-compiled linux-x64 release binary. The
      # tarball is a whole tree — the ELF loads sibling node_modules (native .node addons),
      # a theme dir and a wasm blob — so we install all of it and symlink bin/pi.
      #
      # CRITICAL: a `bun build --compile` binary carries its app bundle as a trailer appended
      # AFTER the ELF, found by byte offset. patchelf AND strip both rewrite the ELF and
      # displace that trailer — after which bun no longer detects the embedded app and the
      # binary degrades to the bare bun CLI (observed: `pi` printed bun's help). So we must
      # NOT patch or strip it. On Arch (this box) the system glibc loader at /lib64 runs it
      # as-is. The eventual NixOS box has no such loader and CANNOT patchelf a bun binary —
      # it needs a wrapper that invokes the store ld-linux without touching the bytes (or
      # nix-ld). Deferred with metal (adopt Nix gradually), tracked here rather than lost.
      pi = pkgs.stdenv.mkDerivation rec {
        pname = "pi-coding-agent";
        version = "0.84.2";

        src = pkgs.fetchurl {
          url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
          hash = "sha256-kG++eH/SJcSsYk/n69Wx1Vpg4PXH71F5XSMVZPnuHBM=";
        };

        sourceRoot = "pi";

        # Keep the bun binary byte-for-byte: no strip, no ELF rewrite, no shebang munging.
        dontStrip = true;
        dontPatchELF = true;
        dontPatchShebangs = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/libexec/pi $out/bin
          cp -r . $out/libexec/pi
          ln -s $out/libexec/pi/pi $out/bin/pi
          runHook postInstall
        '';

        meta = {
          description = "pi — the AI coding-agent harness (prebuilt bun-compiled release binary, unpatched)";
          homepage = "https://github.com/earendil-works/pi";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
          mainProgram = "pi";
        };
      };
    in
    {
      # Exposed as a build target so it can be verified (`nix build .#pi`) without touching
      # the system — the same way funes' package will be. home-manager consumes the same
      # derivation below.
      packages.${system}.pi = pi;

      # funes is an Elixir/OTP app; day-to-day dev runs through mise (matching the box's
      # toolchain). This shell is the reproducible equivalent: Elixir, plus sqlite3 for the
      # 2am repair path. A `mix release` package is a later step — SQLite is the truth, so
      # nothing is lost by packaging the runtime later.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.beamPackages.elixir_1_18 pkgs.sqlite ];
      };

      # The gradual-adoption path: home-manager on the existing Arch install.
      # `home-manager switch --flake .#personalbox` applies the profile without touching the
      # OS. It carries the AI-aware env — pi the harness, plus the manos wiring that makes a
      # pi session a funes citizen — so the whole loop reproduces from this flake.
      homeConfigurations.personalbox = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          # agenix: decrypt age secrets at activation with the box's ssh key (identityPaths
          # defaults to ~/.ssh/id_ed25519 — ours). See the age.secrets block below.
          agenix.homeManagerModules.default
          (
            { lib, ... }:
            let
              # The live repo path — pi loads the REAL extension/skills so a dev edit is
              # picked up (not a stale store snapshot via `self`). Single-user machine: the
              # home dir already fixes this location.
              repo = "/home/andrew/projects/ficciones";
              manosExtension = "${repo}/modules/manos/pi/src/extension.ts";
              # consult — /consult (rich, with session context) and /fresh (thin one-shot):
              # delegate a question to a different model and hand the answer back. The vision
              # case (a text-only main model delegating a screenshot to minimax-m3) is the
              # first use; a general "second opinion" is the same mechanism.
              consultExtension = "${repo}/modules/manos/consult/src/extension.ts";
              # fmt — the agent's format-on-save: mix format any .ex/.exs the edit/write tools
              # touch, so `mix format --check-formatted` in the gate can't fail for an
              # agent-written file. No typecheck here (too heavy per-save); diagnostics are
              # the LSP stack's job, surfaced on demand.
              fmtExtension = "${repo}/modules/manos/fmt/src/extension.ts";
              # lsp — LSP-backed agent tools (hover/definition/references/symbols/diagnostics)
              # over Expert (Elixir), typescript-language-server, nil (Nix), bash-ls, json-ls.
              # See modules/manos/lsp/AGENTS.md. The servers are installed via home.packages
              # above (pkgs.expert / typescript-language-server / nil / bash-language-server /
              # vscode-json-languageserver) so the next box gets them.
              lspExtension = "${repo}/modules/manos/lsp/src/extension.ts";
              manosSkillsGlob = "${repo}/modules/manos/skills/*";

              # funes' self-contained release, built locally by `mise run funes:release`
              # (capability-map move #1; nix builds this same release later — move A). The
              # service below runs it headless; `funes:console`/`:restart` drive the same
              # bin/funes, so node + cookie agree via the release's own env.sh.
              funesRel = "${repo}/modules/funes/_build/prod/rel/funes";

              # funes' MCP server, for pi-mcp-adapter (door 2 — the model's funes tool calls).
              # The URL is env-interpolated by the adapter at connect time. The auth header is
              # a `!command` (pi-mcp-adapter §headers): the adapter runs it at connect and uses
              # stdout as the header value. funes-cli.sh bearer mints a FRESH token against the
              # FUNES_MCP_URL origin's /mint — same world as /mcp, survives a restart / token-
              # model change / secret regeneration (the literal-tmux stale-401 fix). No frozen
              # FUNES_TOKEN. pi-scoped path (~/.pi/agent/mcp.json), no collision with a global
              # ~/.config/mcp/mcp.json a user might keep.
              funesMcpJson = builtins.toJSON {
                mcpServers.funes = {
                  url = "\${FUNES_MCP_URL}";
                  headers.Authorization = "!${repo}/scripts/funes-cli.sh bearer";
                  directTools = [ "post_message" "bank_fact" "raise_issue" "record_done" "get_dossier" ];
                  excludeTools = [ "register" ];
                };
              };

              # pi's provider config (docs.ollama.com/integrations/pi → ~/.pi/agent/models.json).
              # We OWN this file like mcp.json — it is machine config, not something pi writes to
              # (pi's own UI-added models land in the separate models-store.json). Two providers,
              # both OpenAI-compatible:
              #   ollama       — the LOCAL daemon (localhost:11434). apiKey "ollama" is a placeholder
              #                  the daemon ignores; models here must be pulled (`ollama pull …`).
              #   ollama-cloud — ollama.com directly. The one door the OLLAMA_API_KEY opens: pi sends
              #                  the key itself (\${OLLAMA_API_KEY} → pi env-interpolates it, so no
              #                  secret lands in the nix store), and cloud model ids are BARE — no
              #                  ":cloud" suffix (that suffix is only for the local-daemon signin path).
              # The cloud list is a curated coding set from ollama.com/search?c=cloud (Aug 2026);
              # add/remove ids freely — this file is the single source of truth for what pi offers.
              piModelsJson = builtins.toJSON {
                providers = {
                  ollama = {
                    baseUrl = "http://localhost:11434/v1";
                    api = "openai-completions";
                    apiKey = "ollama";
                    models = [ { id = "qwen3-coder"; } ];
                  };
                  "ollama-cloud" = {
                    baseUrl = "https://ollama.com/v1";
                    api = "openai-completions";
                    apiKey = "\${OLLAMA_API_KEY}";
                    models = [
                      { id = "glm-5.2"; }          # Z.ai flagship, long-horizon, 976K ctx (default)
                      { id = "glm-5.1"; }          # leads SWE-Bench Pro — strongest pure agentic-coding
                      { id = "deepseek-v4-pro"; }  # frontier MoE, three reasoning modes
                      { id = "deepseek-v4-flash"; } # efficient MoE, 1M ctx — the cheap/fast everyday tier
                      { id = "kimi-k2.7-code"; }   # Moonshot coding-specialized, ~30% fewer thinking tokens
                      # kimi-k3 removed: ollama.com serves it as EXTRA usage (HTTP 402), not
                      # included in the $20 plan — it bills per-token on top. Keep it out so it
                      # can't be selected by accident. Re-add only if you deliberately want to pay.
                      # native multimodal — the one cloud model that takes images, so the
                      # `input` field is declared and it's the vision target for a /consult
                      # subagent (text-only models like glm-5.2 delegate screenshots here).
                      { id = "minimax-m3"; input = [ "text" "image" ]; }
                    ];
                  };
                };
              };
            in
            {
              home.username = "andrew";
              home.homeDirectory = "/home/andrew";
              home.stateVersion = "25.05";
              programs.home-manager.enable = true;

              # tmux — a first-class stack citizen, flake-managed (adopted from the standalone
              # ~/.config/tmux/tmux.conf repo). Trimmed to what the aleph/Tlön stack needs: mouse,
              # extended-keys (shift+enter round-trips), resurrect+continuum (the Tlön persistence
              # fable's literal-tmux design relies on), yank (OSC 52/wl-copy), tmux-thumbs (hint-
              # label copy for paths/commit-hashes/IDs the agent workflow surfaces). Dropped the
              # chrome that churned alongside the embedded pi: gitmux/tmux-cpu/tmux-battery (status
              # scripts rerunning every status-interval), tmux-which-key, -floating, -autoreload,
              # -mode-indicator, -prefix-highlight, -notify, -pain-control, -better-mouse-mode,
              # -open, -fzf-url, extrakto, -sensible. Lean status bar (session + window tabs, no
              # scripts) — load-bearing in Tlön for seeing/clicking the pi⇄claude windows. The old
              # file is backed up on `home:switch` by the -b flag.
              programs.tmux = {
                enable = true;
                shortcut = "b"; # Ctrl+B prefix (aleph's leader is Ctrl+Space, so no clash)
                escapeTime = 10;
                baseIndex = 1;
                historyLimit = 50000;
                mouse = true;
                terminal = "tmux-256color";
                plugins = with pkgs.tmuxPlugins; [ resurrect continuum yank tmux-thumbs ];
                extraConfig = ''
                  # Extended keys so shift+enter etc. round-trip to apps under tmux (the kitty-
                  # protocol gap the worklist flagged). Apps negotiate their own encoding above this.
                  # csi-u format: pi (and other Kitty-keyboard apps) decode CSI-u most reliably;
                  # pi probes `tmux show -gv extended-keys-format` at startup and warns when it's
                  # the tmux default `xterm`. The Tlön center is a real `tmux attach` into the
                  # user's session, so this is the one line the workbench needs the user's tmux to
                  # carry. Requires tmux 3.5+; this box runs 3.7b.
                  set -s extended-keys on
                  set -g extended-keys-format csi-u
                  set -as terminal-features 'xterm*:extkeys'

                  # Vi mode for the prompt line + copy mode.
                  set -g status-keys vi
                  set -g mode-keys vi
                  bind -T copy-mode-vi v send-keys -X begin-selection
                  bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"

                  # Lean status bar — session + window tabs, NO script churn (gitmux/cpu/battery
                  # dropped). Load-bearing in Tlön: this is how the pi⇄claude windows show/click.
                  set -g status-position top
                  set -g status-interval 15
                  set -g status-style "bg=default,fg=#FFB000"
                  set -g status-left " #S "
                  set -g status-right ""
                  set -g window-status-current-style "fg=#0a0a0a,bg=#FFB000,bold"
                  set -g window-status-current-format " #I #W "
                  set -g window-status-format " #I #W "

                  # Splits + pane nav (prefix chords — the alt- bindings dropped, they clash with
                  # terminal apps like pi/nvim and aren't worth the surface; re-add if you miss them).
                  bind | split-window -h -c "#{pane_current_path}"
                  bind - split-window -v -c "#{pane_current_path}"
                  bind h select-pane -L
                  bind j select-pane -D
                  bind k select-pane -U
                  bind l select-pane -R
                  bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

                  # Tlön persistence: resurrect + continuum restore the standing session across
                  # reboots, with the agent panes in the allowlist so they come back.
                  set -g @continuum-restore 'on'
                  set -g @continuum-save-interval '10'
                  set -g @resurrect-capture-pane-contents 'on'
                  set -g @resurrect-processes 'pi claude "mise exec -- pi" "mise run funes:claude" iex mix nvim vim'

                  # tmux-thumbs: hint-label copy — prefix+F fires hint labels on all visible text.
                  set -g @thumbs-key F
                '';
              };

              # rbw — a Bitwarden CLI with an unlock *agent*, so secrets live in the vault instead
              # of plaintext dotfiles or the nix store. This is the machine's secret-fetch tool: the
              # config here (email, server, pinentry) is non-secret and declarative; the master
              # password + vault stay with Bitwarden. mise resolves OLLAMA_API_KEY via `rbw get`
              # (see mise.toml [env]), which is why the key no longer lives in ~/.config/mise.
              #
              # Server is bitwarden.com for now — set `base_url` to a self-hosted Vaultwarden later
              # (rbw speaks the same API) and nothing else changes. pinentry-curses works in any
              # terminal (ghostty, a tmux pane) — swap to pinentry-gnome3/qt for a GUI prompt.
              # Operational contract: `rbw unlock` once per session so the agent is warm; the
              # non-interactive Tlön pi spawn can't prompt, so a locked vault yields an empty key.
              programs.rbw = {
                enable = true;
                settings = {
                  email = "andrew@lessthanseventy.com";
                  # base_url = "https://vault.example.tld";  # ← self-hosted Vaultwarden goes here
                  # pinentry-qt — a self-contained GUI dialog. Terminal pinentries (curses/tty) EOF'd
                  # because the rbw-agent daemon has no controlling tty; a GUI prompt sidesteps that
                  # and needs no GPG_TTY. qt (not gnome3) because this box is Hyprland/Qt (qt6ct +
                  # kvantum in .zprofile) — pinentry-gnome3 needs GNOME's gcr-prompter service.
                  pinentry = pkgs.pinentry-qt;
                  lock_timeout = 3600;
                };
              };

              # pi — the harness (byte-preserved bun binary, above). watchexec backs
              # scripts/watch.sh's change-triggered test runner (runs-on-change, debounce,
              # .gitignore-aware, restart-on-supersede); declared here so the next box has
              # it, not left to whatever the OS happens to ship.
              #
              # LSP servers for the manos/lsp agent extension (hover/definition/references/
              # diagnostics as pi tools). Flake-managed so the next box gets them, not left to
              # mason or ~/.local/bin. typescript-language-server wraps tsserver; nil is the
              # Nix LSP; bash-language-server for shell; vscode-json-languageserver for JSON.
              # Expert (the Elixir LSP, expert-lsp.org — NOT elixir-ls) is the one exception:
              # it isn't in the pinned nixpkgs yet (added upstream after 2026-08-13), so for
              # now it's installed outside the flake (~/.local/bin/expert) and the adapter
              # spawns it from PATH. When the flake's nixpkgs moves past expert's addition,
              # add pkgs.expert here and it's fully flake-managed. The adapter registry in
              # modules/manos/lsp/src/adapters.ts spawns these by name — adding a language is
              # an adapter object + (usually) a package here.
              home.packages = [
                pi
                pkgs.watchexec
                pkgs.typescript-language-server
                pkgs.nil
                pkgs.bash-language-server
                pkgs.vscode-json-languageserver
                # `agenix -e secrets/<name>.age` to create/edit a secret; decryption at switch is
                # handled by the agenix module (age.secrets below).
                agenix.packages.${system}.default

                # `uqbar` on PATH — type it from anywhere to launch the cockpit, instead of
                # `cd modules/aleph && mise run aleph:run`. NOT named `aleph`: TeX Live ships an
                # `aleph` binary (the Omega/Unicode TeX engine) at /usr/bin, so the name collides.
                # `uqbar` is the Borgesian fit — in "Tlön, Uqbar, Orbis Tertius" (the story that
                # names the dogfood env), Uqbar is the DOORWAY you pass through to reach Tlön, and a
                # launcher is exactly a gateway. Deliberately THIN: it just runs the mise task, so the
                # launch logic (reap a stale cockpit + self-heal an unwired tlon session + mix
                # aleph.run) stays in ONE place (mise.toml), not duplicated here. Dev-mode (recompiles
                # on launch); a self-contained release binary is a later step. Uses the ambient mise
                # (system-installed, on the interactive shell's PATH).
                (pkgs.writeShellScriptBin "uqbar" ''
                  cd ${repo} || { echo "uqbar: repo not found at ${repo}" >&2; exit 1; }
                  exec mise run aleph:run
                '')
              ];

              # Machine secrets — age-encrypted in secrets/, decrypted at home:switch to
              # $XDG_RUNTIME_DIR/agenix/<name> by the box's ssh key. Gated on the .age existing so the
              # flake evaluates before the first secret is created: once `agenix -e
              # secrets/ollama-api-key.age` writes it, this block activates on the next switch and the
              # key lands at /run/user/1000/agenix/ollama-api-key (mise reads it — see mise.toml [env]).
              # No runtime unlock: the non-interactive Tlön pi spawn just finds it there.
              age.secrets = lib.optionalAttrs (builtins.pathExists ./secrets/ollama-api-key.age) {
                ollama-api-key.file = ./secrets/ollama-api-key.age;
              };

              # funes' channel config — we own this file; pi only reads it.
              home.file.".pi/agent/mcp.json".text = funesMcpJson;

              # pi's providers (ollama local + ollama.com cloud) — owned like mcp.json.
              home.file.".pi/agent/models.json".text = piModelsJson;

              # manos into pi's settings.json — MERGED, not owned: pi writes this file (auth,
              # model choice), so a read-only symlink would break it. jq unions our keys in
              # idempotently, seeding {} if absent. This is the declarative install replacing
              # the hand-edit in modules/manos/AGENTS.md.
              #
              # The ollama defaults are seeded with `//=` (set-only-if-absent), NOT `=`: pi
              # persists your runtime model switch (Ctrl+P) back into this same file, and we must
              # not stomp it on every home:switch. So this picks the default the FIRST time and
              # then defers to you. defaultProvider is ollama-cloud/deepseek-v4-flash — the efficient
              # MoE default that drains the short rate-limit window far slower than a reasoning model
              # (glm-5.2's thinking tokens trip it mid-session; see `mise run ollama:usage` to watch).
              # Works the moment OLLAMA_API_KEY is set, no GPU or pull needed. Flip to "ollama"/"qwen3-coder" here
              # (or just switch in-session) to drive a local model instead. enabledModels is the
              # Ctrl+P cycle ring — every id from models.json so all are one keystroke away.
              home.activation.manosWiring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                PI_DIR="$HOME/.pi/agent"
                SETTINGS="$PI_DIR/settings.json"
                run mkdir -p "$PI_DIR"
                [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
                run ${pkgs.jq}/bin/jq \
                  --arg ext "${manosExtension}" \
                  --arg ext2 "${consultExtension}" \
                  --arg ext3 "${fmtExtension}" \
                  --arg ext4 "${lspExtension}" \
                  --arg skills "${manosSkillsGlob}" \
                  '.extensions = ((.extensions // []) + [$ext, $ext2, $ext3, $ext4] | unique)
                   | .skills = ((.skills // []) + [$skills] | unique)
                   | .packages = ((.packages // []) + ["pi-mcp-adapter"] | unique)
                   | .defaultProvider //= "ollama-cloud"
                   | .defaultModel //= "deepseek-v4-flash"
                   | .defaultThinkingLevel //= "medium"
                   | .retry.enabled //= true
                   | .enabledModels //= ["deepseek-v4-flash","glm-5.2","glm-5.1","deepseek-v4-pro","kimi-k2.7-code","minimax-m3","qwen3-coder"]' \
                  "$SETTINGS" > "$SETTINGS.tmp" && run mv "$SETTINGS.tmp" "$SETTINGS"
              '';

              # The always-up sovereign channel (capability-map move #1) as a headless
              # systemd --user service: nothing registers or briefs if the channel isn't
              # up, and until now that was a hand-run iex. A self-contained release
              # (`mise run funes:release`) means ExecStart is one absolute path with no
              # toolchain on PATH. ExecStartPre migrates first — funes never serves on a
              # schema it can't repair (its 2am law). LOOPBACK-only, on the REAL XDG db
              # (FUNES_DB unset → ~/.local/share/funes/wb.db). Node name + cookie come from
              # the release's own env.sh, so `funes:console`/`:restart` reach THIS node.
              # Build the release before the first `home:switch` that starts it;
              # `mise run funes:restart` redeploys a funes change.
              systemd.user.services.funes = {
                Unit = {
                  Description = "funes — the always-up sovereign MCP channel (loopback)";
                  Documentation = [ "file://${repo}/modules/funes/AGENTS.md" ];
                  After = [ "network.target" ];
                };
                Service = {
                  Type = "exec";
                  Environment = [ "FUNES_START_MCP=1" "FUNES_MCP_PORT=4040" ];
                  ExecStartPre = "${funesRel}/bin/funes eval Funes.Release.migrate()";
                  ExecStart = "${funesRel}/bin/funes start";
                  Restart = "on-failure";
                  RestartSec = 2;
                };
                Install.WantedBy = [ "default.target" ];
              };
            }
          )
        ];
      };
    };
}
