# The Claude Code wiring every machine gets, the work Mac too: `session` with /goal and /brief over
# the session records arena's plugin writes in $XDG_RUNTIME_DIR/sessions; the menard-scope hook;
# arena's plugin, whose hooks mark its windows, and babylon's, its tickets' MCP server and hooks;
# and the shells' env, nothing in which waits on a human. Each plugin loads only where its checkout
# exists, and only arena's writes the records: a
# machine without that checkout has `session` but no records. The shell snapshot keeps only PATH,
# so the env cannot live in an rc. No EDITOR: Claude Code's ctrl+g uses it.
# All of it is merged into settings.json, which Claude Code rewrites: the hooks replace any earlier
# copy of themselves (and the session-state and inline arena hooks they grew from) and leave every
# other hook be.
{ lib, pkgs, ... }:
let

  menardScopeBin = pkgs.writeShellScript "menard-scope" (
    "PATH=${pkgs.jq}/bin:${pkgs.coreutils}/bin:$PATH\n" + builtins.readFile ./menard-scope.sh
  );
  allowMerge = builtins.readFile ./allow-merge.jq;

  sessionHooks = pkgs.writeText "session-hooks.json" (
    builtins.toJSON {
      PreToolUse = [
        {
          matcher = "mcp__plugin_menard_menard__(edit|write)";
          hooks = [
            {
              type = "command";
              command = "${menardScopeBin} scope";
            }
          ];
        }
      ];
    }
  );
  allowRules = import ./claude-allow.nix;
  sessionEnv = import ./claude-env.nix;
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "session" (
      "PATH=${pkgs.jq}/bin:$PATH\n" + builtins.readFile ./session.sh
    ))
  ];
  home.file.".claude/skills/goal/SKILL.md".source = ./skills/goal/SKILL.md;
  home.file.".claude/skills/brief/SKILL.md".source = ./skills/brief/SKILL.md;

  # arena and babylon are sibling checkouts; each switch (babylon's install runs one after a landing)
  # loads a store snapshot of their plugin files, not the checkout, so a hook a landing removes
  # cannot break a session that read hooks.json before it (./plugin-snapshot.sh keeps the last few).
  # The routine board tools are allowed outright (auto mode's check otherwise stops a session on
  # them), and so is writing inside a ticket's own worktree (wt's, or babylon's under
  # ~/.cache/babylon/work). menard's edit and write are MCP tools, which the Write/Edit path rules
  # never match, so a PreToolUse hook (./menard-scope.sh) allows them inside those worktrees and
  # leaves every other path to the prompt. Not allowed: answer_proposal, which
  # babylon refuses a Claude anyway, pushes, and deletes.
  home.activation.claudeSessionHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    allow='${builtins.toJSON allowRules}'
    env='${builtins.toJSON sessionEnv}'
    cfg="$HOME/.claude/settings.json"
    record="$HOME/.claude/.ficciones-allow.json"
    prev='[]'
    [ -f "$record" ] && prev=$(cat "$record")
    dead='["Write(~/projects/*/.worktrees/**)","Write(~/.cache/babylon/work/**)"]'
    arena="$HOME/projects/arena"
    has_arena=false
    [ -f "$arena/hooks/hooks.json" ] && has_arena=true
    babylon="$HOME/projects/babylon"
    has_babylon=false
    [ -f "$babylon/hooks/hooks.json" ] && has_babylon=true
    snap() { PATH=/usr/bin:/nix/var/nix/profiles/default/bin:$PATH sh ${./plugin-snapshot.sh} snapshot "$1" "$2" || printf '%s\n' "$1"; }
    arena_dir="$arena"
    babylon_dir="$babylon"
    $has_arena && arena_dir=$(snap "$arena" arena-plugin)
    $has_babylon && babylon_dir=$(snap "$babylon" babylon-plugin)
    [ -f "$cfg" ] || { run mkdir -p "$HOME/.claude"; run sh -c 'echo "{}" > "$1"' _ "$cfg"; }
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile sessions ${sessionHooks} --arg arena "$arena_dir" --arg babylon "$babylon_dir" --arg arena_live "$arena" --arg babylon_live "$babylon" --argjson has_babylon "$has_babylon" --argjson allow "$allow" --argjson env "$env" --argjson prev "$prev" --argjson dead "$dead" --argjson has_arena "$has_arena" '.env += $env
         | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
             | map(select(. != "" and . != $arena_live and . != $babylon_live and (endswith("-arena-plugin") or endswith("-babylon-plugin") | not))) + (if $has_arena then [$arena] else [] end)
               + (if $has_babylon then [$babylon] else [] end) | join(":"))
         | ${allowMerge}
         | .hooks = (((.hooks // {})
             | map_values(map(select(tostring | test("@arena_claude|-session-state |-menard-scope ") | not)))
             | with_entries(select(.value != [])))
           | reduce ($sessions[0] | to_entries[]) as $e (.; .[$e.key] += $e.value))' "$cfg" > "$tmp"; then
        run chmod 600 "$tmp"
        run mv -f "$tmp" "$cfg"
        run sh -c 'printf "%s\n" "$1" > "$2"' _ "$allow" "$record"
      else
        rm -f "$tmp"
      fi
    fi
  '';
}
