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
  writeText,
  dart-sass,
  agsPackages,
}:

let
  astalLibs = with agsPackages; [
    io
    astal4
    hyprland
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
  extra = [ libadwaita libsoup_3 glib-networking ];
  # The palette-generated files (style/_palette.scss, lib/palette.ts) are rewritten from
  # palette.nix before bundling, so the store shell can never disagree with the machine palette
  # even if a checked-in copy drifted (checks.palette-sync catches that for the dev loop).
  generated = import ../theme/generated.nix { inherit lib; };
  shellPrefix = "modules/desktop/shell/";
  bakePalette = lib.concatStrings (
    lib.mapAttrsToList (
      path: text:
      lib.optionalString (lib.hasPrefix shellPrefix path)
        "cp ${writeText (baseNameOf path) text} ${lib.removePrefix shellPrefix path}\n"
    ) generated
  );
  ags = agsPackages.ags.override { extraPackages = astalLibs ++ extra; };
  # The stylesheet per palette, compiled here so the running shell can swap themes without a
  # rebuild: share/astal-shell/themes/<name>.css (home-manager links them into the theme dirs).
  palettes = { uqbar = import ../theme/palettes/uqbar.nix; zahir = import ../theme/palettes/zahir.nix; };
  compileThemes = lib.concatStrings (
    lib.mapAttrsToList (name: p: ''
      cp -r style themestyle-${name}
      cp ${writeText "_palette.scss" (import ../theme/render.nix { inherit lib; palette = p; }).paletteScss} themestyle-${name}/_palette.scss
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

  prePatch = bakePalette;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/astal-shell/themes
    cp -r . $out/share/astal-shell
    ags bundle app.tsx $out/bin/astal-shell -d "SRC='$out/share/astal-shell'"
    ${compileThemes}
    runHook postInstall
  '';

  passthru = { inherit ags astalLibs; };

  meta = {
    description = "ficciones desktop shell — a TUI-native Astal/GTK4 shell on Console.Style";
    mainProgram = "astal-shell";
    platforms = [ "x86_64-linux" ];
  };
}
