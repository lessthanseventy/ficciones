{
  description = "ficciones — one person's whole computer as modules, each a Borges story. funes is the first.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager }:
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
              manosSkillsGlob = "${repo}/modules/manos/skills/*";

              # funes' self-contained release, built locally by `mise run funes:release`
              # (capability-map move #1; nix builds this same release later — move A). The
              # service below runs it headless; `funes:console`/`:restart` drive the same
              # bin/funes, so node + cookie agree via the release's own env.sh.
              funesRel = "${repo}/modules/funes/_build/prod/rel/funes";

              # funes' MCP server, for pi-mcp-adapter. The ${VAR} refs are interpolated by
              # the adapter at connect time from the pane's env (Funes.MCP.Spawn.env prints
              # them). pi-scoped path (~/.pi/agent/mcp.json), so it never collides with a
              # global ~/.config/mcp/mcp.json a user might keep.
              funesMcpJson = builtins.toJSON {
                mcpServers.funes = {
                  url = "\${FUNES_MCP_URL}";
                  headers.Authorization = "Bearer \${FUNES_TOKEN}";
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
              # home-manager refuses to overwrite a file that already exists on disk without a
              # backup strategy (it hard-stops `home:switch` with "would be clobbered"). This
              # happens whenever a `home.file` target is touched outside home-manager — e.g. the
              # models.json direct-patch while iterating, or a file carried over from a prior
              # install. Auto-rename the conflict to `<file>.backup` and write the new one, so
              # `mise run home:switch` never blocks on a stale file again.
              home.backupFileExtension = "backup";
              programs.home-manager.enable = true;

              # pi — the harness (byte-preserved bun binary, above). watchexec backs
              # scripts/watch.sh's change-triggered test runner (runs-on-change, debounce,
              # .gitignore-aware, restart-on-supersede); declared here so the next box has
              # it, not left to whatever the OS happens to ship.
              home.packages = [ pi pkgs.watchexec ];

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
              # then defers to you. defaultProvider is ollama-cloud/glm-5.2 — works the moment
              # OLLAMA_API_KEY is set, no GPU or pull needed. Flip to "ollama"/"qwen3-coder" here
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
                  --arg skills "${manosSkillsGlob}" \
                  '.extensions = ((.extensions // []) + [$ext, $ext2] | unique)
                   | .skills = ((.skills // []) + [$skills] | unique)
                   | .packages = ((.packages // []) + ["pi-mcp-adapter"] | unique)
                   | .defaultProvider //= "ollama-cloud"
                   | .defaultModel //= "glm-5.2"
                   | .defaultThinkingLevel //= "medium"
                   | .retry.enabled //= true
                   | .enabledModels //= ["glm-5.2","glm-5.1","deepseek-v4-pro","deepseek-v4-flash","kimi-k2.7-code","minimax-m3","qwen3-coder"]' \
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
