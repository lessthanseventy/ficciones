# home-manager: every themed surface written from palette.nix (render.nix). The shell gets
# its own IN the repo (generated.nix, `mise theme:gen`); everything here lands in
# ~/.config and is a store file — none of it is edited by hand, so nothing needs to be live.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ficciones.desktop.theme;
  palette = import ./palette.nix;
  render = import ./render.nix { inherit lib palette; };
  tpl = name: builtins.readFile (./templates + "/${name}");

  # EVERY palette rendered at install: each surface has a copy per palette (palettes/default.nix)
  # under ~/.config/ficciones/themes/<name>/, each app's fixed path is a symlink through
  # ~/.config/ficciones/theme (the one mutable link, made on activation if missing), and the
  # toggle repoints it — no nix, under a second. `palette.nix`/`current` remain the build-time
  # default (the checked-in generated files).
  palettes = import ./palettes;
  renders = lib.mapAttrs (
    _: p:
    import ./render.nix {
      inherit lib;
      palette = p;
    }
  ) palettes;
  # the dark GTK theme hard-codes dark surfaces; a light palette starts from Adwaita
  gtkThemeOf = r: if r.desktop.light then "Adwaita" else cfg.gtkTheme;
  cursorThemes = lib.unique (lib.mapAttrsToList (_: r: r.desktop.cursor) renders);
  envLua =
    r:
    "hl.env(\"GTK_THEME\", \"${gtkThemeOf r}\")\n"
    + "hl.env(\"XCURSOR_THEME\", \"${r.desktop.cursor}\")\n"
    + "hl.env(\"HYPRCURSOR_THEME\", \"${r.desktop.cursor}\")\n"
    + "hl.env(\"QT_QPA_PLATFORMTHEME\", \"${cfg.qtPlatformTheme}\")\n"
    + lib.optionalString (
      cfg.qtPlatformTheme == "qt6ct"
    ) "hl.env(\"QT_STYLE_OVERRIDE\", \"kvantum\")\n";
  # a ruled sheet in the palette's own paper and ink, so a paper palette's backdrop photo is paper
  paperSheet =
    {
      ground,
      rule,
      margin,
    }:
    pkgs.runCommand "paper-${lib.removePrefix "#" ground}.jpg"
      { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        lines=""
        for y in $(seq 96 56 1440); do lines="$lines line 0,$y 2560,$y"; done
        magick -size 2560x1440 "xc:${ground}" -attenuate 0.08 +noise Gaussian \
          -stroke "${rule}" -strokewidth 1 -draw "$lines" \
          -stroke "${margin}" -draw "line 240,0 240,1440" -quality 88 "$out"
      '';
  themeFiles = r: {
    "ghostty-theme" = r.ghosttyTheme;
    "ghostty.css" = r.ghosttyCss;
    "kitty-theme.conf" = r.kittyTheme;
    "wezterm.toml" = r.weztermTheme;
    "gtk.css" = r.gtkCss;
    "qt6ct-colors.conf" = r.qt6ctColors;
    "qt.qss" = r.qss;
    "kvantum.kvconfig" = r.kvantumConfig;
    "kvantum.svg" = r.kvantumSvg;
    "btop.theme" = r.btopTheme;
    "hypr-theme.lua" = r.hyprlandThemeLua + envLua r;
    "desktop.json" = builtins.toJSON {
      gtkTheme = gtkThemeOf r;
      inherit (r.desktop) iconTheme;
      cursorTheme = r.desktop.cursor;
    };
    "gtk3-settings.ini" =
      r.gtkSettingsIni
      + "gtk-application-prefer-dark-theme=${
        lib.boolToString (!r.desktop.light)
      }\ngtk-theme-name=${gtkThemeOf r}\n";
    # libadwaita refuses gtk-application-prefer-dark-theme (a warning at every shell start); GTK 4
    # takes the scheme from the portal's color-scheme, which the theme switch sets
    "gtk4-settings.ini" = r.gtkSettingsIni + "gtk-theme-name=${gtkThemeOf r}\n";
    "hyprlock.conf" = r.hyprlockConf;
    "lazygit.yml" = r.lazygitConfig (tpl "lazygit.yml");
    "starship.toml" = r.starshipConfig (tpl "starship.toml");
    "bat-config" = r.batConfig;
    "fzf.zsh" = r.fzfTheme;
    "cava.conf" = r.cavaConfig (tpl "cava.conf");
    "burn-close.glsl" = r.burnCloseGlsl (tpl "burn-close.glsl");
    "tmux.conf" = r.tmuxStyle;
    "palette.sh" = r.envSh;
    "shell-palette.json" = r.paletteJson;
    "wallpapers.json" =
      if r.desktop.paper then builtins.toJSON [ "${paperSheet r.desktop.sheet}" ] else r.wallpapersJson;
    "steam.css" = r.steamCss;
    "claude-powerline.json" = r.claudePowerlineJson;
    "web.css" = r.webCss;
    "floorp-userChrome.css" = r.floorpUserChrome;
    "floorp-userContent.css" = r.floorpUserContent;
    "floorp-page.json" = r.floorpPageJson;
  };
  themeDir = "${config.xdg.configHome}/ficciones/theme";
  fontconfigFiles =
    let
      prefer = fams: lib.concatMapStrings (f: "            <family>${f}</family>\n") fams;
      alias =
        name: fams:
        "  <alias binding=\"same\">\n    <family>${name}</family>\n    <prefer>\n${prefer fams}    </prefer>\n  </alias>\n";
      mono = [
        palette.font.family
        palette.font.mono
        "Noto Sans Mono"
        "Noto Sans CJK SC"
        "Noto Color Emoji"
      ];
      sans = [
        palette.font.family
        "Noto Sans"
        "Noto Sans CJK SC"
        "Noto Color Emoji"
      ];
      profile = config.home.profileDirectory;
    in
    pkgs.runCommand "ficciones-fontconfig" { } ''
      mkdir -p $out
      cat > $out/10-ficciones-fonts.conf <<EOF
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <description>fonts from the Nix user profile (modules/desktop/theme)</description>
        <dir>${profile}/share/fonts</dir>
        <dir>${profile}/lib/X11/fonts</dir>
      </fontconfig>
      EOF
      cat > $out/52-ficciones-default-fonts.conf <<EOF
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
      ${alias "monospace" mono}${alias "sans-serif" sans}${alias "serif" sans}${
        alias "emoji" [ "Noto Color Emoji" ]
      }</fontconfig>
      EOF
      sed -i 's/^      //' $out/*.conf
    '';
  # pages get the desktop's light/dark, which the theme switch sets, instead of forced dark
  followScheme = "user_pref(\"layout.css.prefers-color-scheme.content-override\", 2);\n";
  # an app's fixed path → the theme dir's copy, through the one mutable link
  via = file: { source = config.lib.file.mkOutOfStoreSymlink "${themeDir}/${file}"; };
in
{
  options.ficciones.desktop.theme = {
    palette = lib.mkOption {
      type = lib.types.attrs;
      default = palette;
      readOnly = true;
      description = "The palette (modules/desktop/theme/palette.nix), for other modules that need a value.";
    };
    render = lib.mkOption {
      type = lib.types.attrs;
      default = render;
      readOnly = true;
      description = "The rendered surfaces (render.nix): flake.nix splices tmuxStyle from here.";
    };
    floorpProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "d0p2n4mq.default-nightly-1725500522201" ];
      description = "Profile directories under ~/.floorp that get the floorp-ext extension, which loads the theme's sheets live.";
    };
    firefoxProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1ikkcccb.default-release-1775251914567" ];
      description = "Profile directories under ~/.mozilla/firefox that get the same userChrome.css/userContent.css as floorp.";
    };
    qtPlatformTheme = lib.mkOption {
      type = lib.types.enum [
        "qt6ct"
        "gtk3"
      ];
      default = "gtk3";
      description = ''
        How Qt apps get the palette. "qt6ct" (+ kvantum) is the real thing and what modules/os
        installs; "gtk3" is Qt's own platform theme, which derives a palette from the GTK theme
        and our gtk.css — the honest choice on the Arch box, where qt6ct was never installed.
      '';
    };
    gtkTheme = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha-yellow-standard+default";
      description = ''
        The GTK theme under the @define-color overrides — the overrides carry the palette, the
        theme carries widget shapes. Installed by the OS (pacman today, fonts/themes in modules/os later).
      '';
    };
  };

  config = {
    # the one font, plus coverage for what it has no glyphs for: non-Latin text and emoji
    home.packages = [
      pkgs.nerd-fonts.comic-shanns-mono
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji
    ];
    # fontconfig, by hand rather than fonts.fontconfig.enable: home-manager re-links its conf.d
    # files at EVERY switch, fontconfig's timestamp bumps, GTK broadcasts it, and ghostty
    # re-initialises its bundled fontconfig and segfaults in FcPatternDestroy (16:33 on
    # 2026-09-07, with a Claude session inside it). These two files are written only when their
    # content changes, from paths that do not change (~/.nix-profile, not the store path).
    # Every generic family resolves to THE font — mono for sans and serif too (Andrew: easier on
    # his eyes than any proportional face); Noto only fills the glyphs it lacks.
    home.activation.fontconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      d="${config.xdg.configHome}/fontconfig/conf.d"; run mkdir -p "$d"
      for f in ${fontconfigFiles}/*.conf; do
        if ! cmp -s "$f" "$d/$(basename "$f")"; then run install -m644 "$f" "$d/$(basename "$f")"; fi
      done
      # the cache follows the profile's font set, not the switch
      stamp="${config.xdg.cacheHome}/fontconfig/.ficciones-fonts"
      cur="$(readlink -f "${config.home.profileDirectory}/share/fonts" 2>/dev/null || true)"
      if [ "$(cat "$stamp" 2>/dev/null)" != "$cur" ]; then run ${pkgs.fontconfig}/bin/fc-cache -f >/dev/null 2>&1 || true; run sh -c 'printf %s "$1" > "$2"' _ "$cur" "$stamp"; fi
    '';

    # GTK reads org.gnome.desktop.interface AHEAD of settings.ini on Wayland, and a D-Bus-activated
    # app (gcr-prompter, the portal dialogs) never sees Hyprland's GTK_THEME — a stale
    # `adw-gtk3-dark` here (caelestia's) left every one of those on stock Adwaita light.
    # color-scheme, gtk-theme, icon-theme and cursor-theme are NOT declared: the shell's theme
    # switch owns them live, and at its start (lib/theme.ts, from the palette's desktop.json).
    dconf.settings."org/gnome/desktop/interface" = {
      font-name = "${palette.font.family} ${toString palette.font.size}";
      cursor-size = 24;
    };

    xdg.configFile = lib.mkMerge [
      # every surface, every palette
      (lib.mkMerge (
        lib.mapAttrsToList (
          name: r:
          lib.mapAttrs' (file: text: lib.nameValuePair "ficciones/themes/${name}/${file}" { inherit text; }) (
            themeFiles r
          )
          // {
            # the shell's stylesheet for this palette, compiled in the shell package
            "ficciones/themes/${name}/shell.css".source =
              "${config.ficciones.desktop.shell.package}/share/astal-shell/themes/${name}.css";
            # Claude Code: ONE theme name, whose contents change with the palette. It watches
            # ~/.claude/themes for content changes (watchCustomThemes/reloadCustomThemes) and reads
            # the `theme` key in settings.json only at startup — so naming a different file per
            # palette, which is what we used to do, could never switch a running session.
            "ficciones/themes/${name}/claude-theme.json".text = r.claudeTheme {
              name = "ficciones";
              inherit (palettes.${name}) light;
            };
            # Neovim (asterion, a sibling repo): roles + base16 as a Lua table, read at startup.
            "ficciones/themes/${name}/nvim-palette.lua".text = r.nvimPalette {
              inherit name;
              inherit (palettes.${name}) light;
            };
          }
        ) renders
      ))
      {
        # ghostty: the theme file + the config that names it (templates/ghostty.conf is the rest).
        "ghostty/themes/ficciones" = via "ghostty-theme";
        "ghostty/config".text = render.ghosttyConfig (tpl "ghostty.conf");

        # kitty / wezterm — theme files only; each config includes its own (comment in the file).
        "kitty/theme.conf" = via "kitty-theme.conf";
        "wezterm/colors/ficciones.toml" = via "wezterm.toml";

        # GTK 3/4: libadwaita's named colours + the font, over whichever theme draws the widgets.
        "gtk-3.0/gtk.css" = via "gtk.css";
        "gtk-4.0/gtk.css" = via "gtk.css";

        # starship reads it at every prompt: the switch lands on the next line
        "starship.toml" = via "starship.toml";
        "gtk-3.0/settings.ini" = via "gtk3-settings.ini";
        "gtk-4.0/settings.ini" = via "gtk4-settings.ini";
        "millennium/quick.css" = via "steam.css";

        # Qt: qt6ct owns the palette + font, kvantum draws the widgets, the qss covers what neither reaches.
        "qt6ct/qt6ct.conf".text = render.qt6ctConf;
        "qt6ct/colors/ficciones.conf" = via "qt6ct-colors.conf";
        "qt6ct/qss/ficciones.qss" = via "qt.qss";
        "qt5ct/qt5ct.conf".text = builtins.replaceStrings [ "qt6ct" ] [ "qt5ct" ] render.qt6ctConf;
        "qt5ct/colors/ficciones.conf" = via "qt6ct-colors.conf";
        "qt5ct/qss/ficciones.qss" = via "qt.qss";
        "Kvantum/kvantum.kvconfig".text = "[General]\ntheme=ficciones\n";
        "Kvantum/ficciones/ficciones.kvconfig" = via "kvantum.kvconfig";
        "Kvantum/ficciones/ficciones.svg" = via "kvantum.svg";

        "btop/themes/ficciones.theme" = via "btop.theme";

        # Hyprland colours (dofile'd by hyprland.lua) and the lock screen.
        "hypr/theme.lua" = via "hypr-theme.lua";
        "hypr/hyprlock.conf" = via "hyprlock.conf";

        "lazygit/config.yml" = via "lazygit.yml";
        "bat/config" = via "bat-config";
        "fzf/theme.zsh" = via "fzf.zsh";
        "cava/config" = via "cava.conf";

        # The palette as shell variables, for scripts that draw.
        "ficciones/palette.sh" = via "palette.sh";
        # tlon's office TUI takes its roles from here, and follows the link on a switch.
        "tlon/palette.json" = via "shell-palette.json";
      }
    ];

    # ~/.claude/themes/ficciones.json is NOT declared here: it is mutable, seeded by the
    # activation below and thereafter owned by the toggle, the same deal as the theme link.
    home.file = {
      # the statusline (scripts/statusline-box.sh) and its renderer's config, per theme
      ".claude/statusline-box.sh" = {
        source = ../scripts/statusline-box.sh;
        executable = true;
      };
      ".claude/claude-powerline.json" = via "claude-powerline.json";
    }
    # in ~/.icons, the path every cursor reader searches, not only those that take XDG_DATA_DIRS
    // lib.genAttrs (map (c: ".icons/${c}") cursorThemes) (n: {
      source = "${pkgs.bibata-cursors}/share/icons/${lib.removePrefix ".icons/" n}";
    })
    // lib.listToAttrs (
      lib.concatMap (profile: [
        (lib.nameValuePair ".mozilla/firefox/${profile}/chrome/userChrome.css" (
          via "floorp-userChrome.css"
        ))
        (lib.nameValuePair ".mozilla/firefox/${profile}/chrome/userContent.css" (
          via "floorp-userContent.css"
        ))
        # floorp reads chrome/*.css by default; Firefox only with this pref, and user.js is re-applied every start
        (lib.nameValuePair ".mozilla/firefox/${profile}/user.js" {
          text = "user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);\n${followScheme}";
        })
      ]) cfg.firefoxProfiles
    );

    # the one mutable link: made once, then owned by the toggle (astal-shell theme / Super+Shift+P)
    home.activation.ficcionesTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # a fresh home (the VM, a new install) has no ~/.config/ficciones yet; the themes/ tree
      # under it is linked by linkGeneration, which runs later in the same activation
      run mkdir -p "$(dirname "${themeDir}")"
      if [ ! -e "${themeDir}" ]; then run ln -sfn themes/uqbar "${themeDir}"; fi
    '';

    # Claude Code reads the `theme` key at startup and then WATCHES the theme file itself, so the
    # name has to be constant and the contents have to change under it. Seeded here from whichever
    # palette is live; the toggle rewrites it on every switch. Deliberately a real file, not a link
    # into the theme dir: repointing a link fires no event in the directory being watched.
    # AFTER linkGeneration: the theme dir it copies from is linked in that step, so running any
    # earlier finds nothing to copy and leaves Claude Code pointed at a theme that is not there.
    home.activation.ficcionesClaudeTheme =
      lib.hm.dag.entryAfter [ "ficcionesTheme" "linkGeneration" ]
        ''
          run mkdir -p "$HOME/.claude/themes"
          src="${themeDir}/claude-theme.json"
          # the source is a store path (mode 444); the toggle has to be able to overwrite the copy
          if [ -r "$src" ]; then
            run cp -f "$src" "$HOME/.claude/themes/ficciones.json"
            run chmod u+w "$HOME/.claude/themes/ficciones.json"
          fi
          # the old per-palette names are gone; a stale `theme` key would silently pin one of them
          run rm -f "$HOME/.claude/themes/uqbar.json" "$HOME/.claude/themes/zahir.json"
          cfg="$HOME/.claude/settings.json"
          if [ -f "$cfg" ]; then
            tmp=$(mktemp)
            if ${pkgs.jq}/bin/jq '.theme = "custom:ficciones"' "$cfg" > "$tmp"; then
              run mv -f "$tmp" "$cfg"
            else
              rm -f "$tmp"
            fi
          fi
        '';

    # floorp's user.js is kept by hand, so only these lines are ours. The extension is copied, not
    # linked: floorp notices an update by mtime, and every store path has the same one.
    home.activation.floorpExtension = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStrings (profile: ''
        dir="$HOME/.floorp/${profile}"
        if [ -f "$dir/user.js" ]; then
          printf '%s' ${lib.escapeShellArg followScheme} | cat - ${./floorp-ext/user.js} | while IFS= read -r line; do
            grep -qF "$line" "$dir/user.js" || printf '%s\n' "$line" >> "$dir/user.js"
          done
          xpi=${pkgs.callPackage ./floorp-ext { }}
          if ! cmp -s "$xpi" "$dir/extensions/theme@ficciones.xpi"; then
            run install -Dm644 "$xpi" "$dir/extensions/theme@ficciones.xpi"
          fi
        fi
      '') cfg.floorpProfiles
    );

    # btop rewrites btop.conf on exit, so it stays a real file; only the theme line is ours.
    home.activation.btopTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      conf="$HOME/.config/btop/btop.conf"
      if [ -f "$conf" ] && ! grep -q '^color_theme = "ficciones"' "$conf"; then
        run ${pkgs.gnused}/bin/sed -i 's/^color_theme = .*/color_theme = "ficciones"/' "$conf"
      fi
    '';
  };
}
