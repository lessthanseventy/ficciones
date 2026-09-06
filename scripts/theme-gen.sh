#!/usr/bin/env bash
# Write the palette-generated files into the working tree (modules/desktop/theme/generated.nix).
# `--check` only diffs, exit 1 on drift — the same test flake `checks.palette-sync` runs.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-write}"
json="$(nix eval --json --impure --expr \
  'import ./modules/desktop/theme/generated.nix { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }')"
rc=0
while IFS= read -r path; do
  if [ "$mode" = "--check" ]; then
    if ! diff -u "$path" <(jq -j --arg p "$path" '.[$p]' <<<"$json") >/dev/null 2>&1; then
      echo "theme:gen — $path drifts from palette.nix (run: mise theme:gen)"; rc=1
    fi
  else
    jq -j --arg p "$path" '.[$p]' <<<"$json" >"$path"; echo "theme:gen — wrote $path"
  fi
done < <(jq -r 'keys[]' <<<"$json")
exit $rc
