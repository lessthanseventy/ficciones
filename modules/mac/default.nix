# home-manager on the work Mac: the palette's portable surfaces (terminals, prompt, TUIs, Floorp,
# Claude Code) from the same render.nix and palettes/ as the Linux box. No desktop, no shell, no
# dotfiles that carry the work identity (zshrc, gitconfig, CLAUDE.md stay the Mac's own).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ficciones.mac;
  theme = ../desktop/theme;
  palettes = import (theme + "/palettes");
  renders = lib.mapAttrs (_: p: import (theme + "/render.nix") { inherit lib; palette = p; }) palettes;
  tpl = name: builtins.readFile (theme + "/templates/${name}");

  themeFiles = r: {
    "ghostty-theme" = r.ghosttyTheme;
    "kitty-theme.conf" = r.kittyTheme;
    "wezterm.toml" = r.weztermTheme;
    "btop.theme" = r.btopTheme;
    "lazygit.yml" = r.lazygitConfig (tpl "lazygit.yml");
    "starship.toml" = r.starshipConfig (tpl "starship.toml");
    "bat-config" = r.batConfig;
    "fzf.zsh" = r.fzfTheme;
    "tmux.conf" = r.tmuxStyle;
    "palette.sh" = r.envSh;
    "shell-palette.json" = r.paletteJson;
    "web.css" = r.webCss;
    "floorp-userChrome.css" = r.floorpUserChrome;
    "floorp-userContent.css" = r.floorpUserContent;
    "floorp-page.json" = r.floorpPageJson;
    "claude-powerline.json" = r.claudePowerlineJson;
  };
  themeDir = "${config.xdg.configHome}/ficciones/theme";
  via = file: { source = config.lib.file.mkOutOfStoreSymlink "${themeDir}/${file}"; };
  followScheme = "user_pref(\"layout.css.prefers-color-scheme.content-override\", 2);\n";
  statusline = pkgs.writeShellScript "statusline-box" ''
    export CLAUDE_POWERLINE=${pkgs.claude-powerline}/bin/claude-powerline
    export PATH=${lib.makeBinPath [ pkgs.bash pkgs.jq pkgs.python3 pkgs.gawk pkgs.gnused pkgs.coreutils ]}:$PATH
    exec bash ${../desktop/scripts/statusline-box.sh}
  '';
  floorpRoot = "${config.home.homeDirectory}/Library/Application Support/Floorp/Profiles";
in
{
  options.ficciones.mac = {
    floorpProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tms5igu1.default-release-1750259455148" ];
      description = "Profile directories under ~/Library/Application Support/Floorp/Profiles that get the floorp-ext extension.";
    };
    defaultPalette = lib.mkOption {
      type = lib.types.str;
      default = "uqbar";
      description = "The palette the theme link is made with on first activation; `ficciones-theme <name>` owns it after.";
    };
  };

  config = {
    xdg.enable = true;

    home.packages = [
      pkgs.delta
      (pkgs.writeShellScriptBin "ficciones-theme" (builtins.readFile ./ficciones-theme))
      (pkgs.writeShellScriptBin "ficciones-recolor" (
        builtins.readFile ../desktop/scripts/ficciones-recolor
      ))
    ];

    xdg.configFile = lib.mkMerge [
      (lib.mkMerge (
        lib.mapAttrsToList (
          name: r:
          lib.mapAttrs' (file: text: lib.nameValuePair "ficciones/themes/${name}/${file}" { inherit text; }) (
            themeFiles r
          )
          // {
            "ficciones/themes/${name}/claude-theme.json".text = r.claudeTheme {
              name = "ficciones";
              inherit (palettes.${name}) light;
            };
            "ficciones/themes/${name}/nvim-palette.lua".text = r.nvimPalette {
              inherit name;
              inherit (palettes.${name}) light;
            };
          }
        ) renders
      ))
      {
        "ghostty/themes/ficciones" = via "ghostty-theme";
        "ghostty/config".text =
          (import (theme + "/render.nix") { inherit lib; palette = import (theme + "/palette.nix"); })
          .ghosttyConfig (tpl "ghostty-mac.conf");
        "kitty/theme.conf" = via "kitty-theme.conf";
        "wezterm/colors/ficciones.toml" = via "wezterm.toml";
        "starship.toml" = via "starship.toml";
        "bat/config" = via "bat-config";
        "fzf/theme.zsh" = via "fzf.zsh";
        "btop/themes/ficciones.theme" = via "btop.theme";
        "ficciones/palette.sh" = via "palette.sh";
        "tlon/palette.json" = via "shell-palette.json";
        "aerospace/aerospace.toml".source = ./aerospace.toml;
        # Karabiner's settings UI can't save through this read-only link; edit the repo copy.
        "karabiner/karabiner.json".source = ./karabiner.json;
      }
    ];

    # lazygit reads here on macOS unless XDG_CONFIG_HOME is set
    home.file."Library/Application Support/lazygit/config.yml" = via "lazygit.yml";
    home.file.".claude/statusline-box.sh".source = statusline;
    home.file.".claude/claude-powerline.json" = via "claude-powerline.json";

    home.activation.ficcionesTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$(dirname "${themeDir}")"
      if [ ! -e "${themeDir}" ]; then run ln -sfn themes/${cfg.defaultPalette} "${themeDir}"; fi
    '';

    home.activation.ficcionesClaudeTheme =
      lib.hm.dag.entryAfter [ "ficcionesTheme" "linkGeneration" ]
        ''
          run mkdir -p "$HOME/.claude/themes"
          src="${themeDir}/claude-theme.json"
          if [ -r "$src" ]; then
            run cp -f "$src" "$HOME/.claude/themes/ficciones.json"
            run chmod u+w "$HOME/.claude/themes/ficciones.json"
          fi
          f="$HOME/.claude/settings.json"
          if [ -f "$f" ]; then
            tmp=$(mktemp)
            # the Mac's own plugin dirs stay; only the changes pane's store path is swapped in
            if ${pkgs.jq}/bin/jq --arg pane "${../agents/mods/changes-pane}" '.theme = "custom:ficciones"
                 | .statusLine = {type: "command", command: "~/.claude/statusline-box.sh"}
                 | .autoCompactWindow = 400000
                 | .enabledPlugins["cc-plugin-diff@builtin"] = false
                 | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
                     | map(select(. != "" and (endswith("-changes-pane") | not))) + [$pane] | join(":"))' "$f" > "$tmp"; then
              run mv -f "$tmp" "$f"
            else
              rm -f "$tmp"
            fi
          fi
          # the built-in diff sidebar opens on an edit otherwise and leaves the changes pane no columns
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

    # Floorp keeps its user.js by hand, so only these lines are ours; the xpi is copied (mtime is
    # how Floorp notices an update, and every store path has the same one)
    home.activation.floorpExtension = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (profile: ''
        dir=${lib.escapeShellArg "${floorpRoot}/${profile}"}
        if [ -d "$dir" ]; then
          run touch "$dir/user.js"
          printf '%s' ${lib.escapeShellArg followScheme} | cat - ${theme + "/floorp-ext/user.js"} | while IFS= read -r line; do
            grep -qF "$line" "$dir/user.js" || run sh -c 'printf "%s\n" "$1" >> "$2"' _ "$line" "$dir/user.js"
          done
          xpi=${pkgs.callPackage (theme + "/floorp-ext") { }}
          if ! cmp -s "$xpi" "$dir/extensions/theme@ficciones.xpi"; then
            run mkdir -p "$dir/extensions"
            run install -m644 "$xpi" "$dir/extensions/theme@ficciones.xpi"
          fi
        fi
      '') cfg.floorpProfiles
    );

    home.activation.btopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="$HOME/.config/btop/btop.conf"
      if [ -f "$conf" ] && ! grep -q '^color_theme = "ficciones"' "$conf"; then
        run ${pkgs.gnused}/bin/sed -i 's/^color_theme = .*/color_theme = "ficciones"/' "$conf"
      fi
    '';
  };
}
