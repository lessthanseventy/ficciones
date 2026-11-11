# The shell as a store package: `ags bundle` (esbuild + dart-sass) over this directory, wrapped
# so gjs finds every Astal typelib. Built for the VM and for `nix build .#astal-shell`; the
# dev loop on a live desktop is `ags run` over the working tree instead (mise shell:dev).
{
  lib,
  stdenv,
  wrapGAppsHook3,
  gobject-introspection,
  gjs,
  libadwaita,
  libsoup_3,
  glib-networking,
  vte-gtk4,
  writeText,
  runtimeShell,
  dart-sass,
  agsPackages,
  tlon,
}:

let
  astalLibs = with agsPackages; [
    io
    astal4
    # Hyprland 0.57 gives a special workspace an address and no id; unpatched, every sync
    # logs a Json-CRITICAL per special workspace and files them all under id 0.
    (hyprland.overrideAttrs (o: {
      patches = (o.patches or [ ]) ++ [ ../patches/astal-hyprland-workspace-address.patch ];
    }))
    battery
    network
    wireplumber
    tray
    notifd
    mpris
    powerprofiles
    bluetooth
    apps
    cava
    brightness
  ];
  # glib-networking: GIO's TLS backend, or every https fetch dies with "TLS support is not
  # available". wrapGAppsHook3 turns it into GIO_EXTRA_MODULES on both wrappers.
  # vte-gtk4: the office's wide view embeds a worker's real terminal (their tmux window).
  extra = [
    libadwaita
    libsoup_3
    glib-networking
    vte-gtk4
  ];
  # The palette-generated files (style/_palette.scss, lib/palette.ts) are rewritten from
  # palette.nix before bundling, so the store shell can never disagree with the machine palette
  # even if a checked-in copy drifted (checks.palette-sync catches that for the dev loop).
  generated = import ../theme/generated.nix { inherit lib; };
  shellPrefix = "modules/desktop/shell/";
  bakePalette = lib.concatStrings (
    lib.mapAttrsToList (
      path: text:
      lib.optionalString (lib.hasPrefix shellPrefix path) "cp ${writeText (baseNameOf path) text} ${lib.removePrefix shellPrefix path}\n"
    ) generated
  );
  ags = agsPackages.ags.override { extraPackages = astalLibs ++ extra; };
  # The stylesheet per palette, compiled here so the running shell can swap themes without a
  # rebuild: share/astal-shell/themes/<name>.css (home-manager links them into the theme dirs).
  palettes = import ../theme/palettes;
  compileThemes = lib.concatStrings (
    lib.mapAttrsToList (name: p: ''
      cp -r style themestyle-${name}
      cp ${
        writeText "_palette.scss"
          (import ../theme/render.nix {
            inherit lib;
            palette = p;
          }).paletteScss
      } themestyle-${name}/_palette.scss
      sass --no-source-map themestyle-${name}/main.scss $out/share/astal-shell/themes/${name}.css
    '') palettes
  );
in
stdenv.mkDerivation {
  pname = "astal-shell";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _: !(lib.hasInfix "/node_modules" path || lib.hasInfix "/@girs" path);
  };

  nativeBuildInputs = [
    wrapGAppsHook3
    gobject-introspection
    ags
    dart-sass
  ];
  buildInputs = astalLibs ++ [ gjs ] ++ extra;

  # office/ holds links into the live tlon checkout for the dev loop; the store build takes the
  # same two directories from the pinned tlon input instead
  prePatch = bakePalette + ''
    rm -rf office && mkdir office
    cp -r ${tlon}/office/kit ${tlon}/office/rooms office/
    chmod -R u+w office
  '';

  # The shell brings its own stylesheet; a GTK_THEME from the session (theme.lua sets one for
  # the other GTK apps) would paint under it — grey popovers and bars.
  preFixup = ''
    gappsWrapperArgs+=(--unset GTK_THEME)
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec $out/share/astal-shell/themes
    cp -r . $out/share/astal-shell
    ags bundle app.tsx $out/libexec/astal-shell -d "SRC='$out/share/astal-shell'"
    ${compileThemes}
    runHook postInstall
  '';

  # A verb goes straight to the running shell: the bundle takes over a second to load, only to
  # forward it. Written after the wrap hook, which would put its own start-up in front of this too.
  postFixup = ''
    cat > $out/bin/astal-shell <<EOF
    #!${runtimeShell}
    [ \$# -gt 0 ] && exec ${ags}/bin/ags request -i astal-shell "\$@"
    exec $out/libexec/astal-shell
    EOF
    chmod +x $out/bin/astal-shell
  '';

  passthru = { inherit ags astalLibs; };

  meta = {
    description = "ficciones desktop shell — a TUI-native Astal/GTK4 shell on the machine palette";
    mainProgram = "astal-shell";
    platforms = [ "x86_64-linux" ];
  };
}
