# Unsigned: Floorp's nightly channel loads it with the prefs in theme/default.nix.
{
  runCommand,
  fetchurl,
  zip,
}:
let
  darkreader = fetchurl {
    url = "https://registry.npmjs.org/darkreader/-/darkreader-4.9.134.tgz";
    hash = "sha512-HAyEz97vK/UFLO6kcjxojji5OKr0+pwgGLrBzyg67xD2p6ySrSyCBvNxb+0KTSMYk9qNz9Hq85JR3TaKyqEV1w==";
  };
in
runCommand "ficciones-floorp.xpi" { nativeBuildInputs = [ zip ]; } ''
  cp ${./manifest.json} manifest.json
  cp ${./schema.json} schema.json
  cp ${./api.js} api.js
  cp ${./background.js} background.js
  cp ${./page.js} page.js
  cp ${./popup.html} popup.html
  cp ${./popup.js} popup.js
  tar -xzf ${darkreader} --strip-components=1 package/darkreader.js
  zip -X -q "$out" manifest.json schema.json api.js background.js page.js popup.html popup.js darkreader.js
''
