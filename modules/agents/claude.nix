# The Claude Code wiring every machine gets, the work Mac too: `session` with /goal and /brief over
# the session records arena's plugin writes in $XDG_RUNTIME_DIR/sessions; the menard-scope hook;
# arena's plugin, whose hooks mark its windows; and the shells' env, nothing in which waits on a
# human. The plugin loads only where ~/projects/arena exists, and only it writes the records: a
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
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "session" (
      "PATH=${pkgs.jq}/bin:$PATH\n" + builtins.readFile ./session.sh
    ))
  ];
  home.file.".claude/skills/goal/SKILL.md".source = ./skills/goal/SKILL.md;
  home.file.".claude/skills/brief/SKILL.md".source = ./skills/brief/SKILL.md;

  # arena is a sibling checkout, loaded from where it is so a pull there is the update.
  # The routine board tools are allowed outright (auto mode's check otherwise stops a session on
  # them), and so is writing inside a ticket's own worktree (wt's, or babylon's under
  # ~/.cache/babylon/work). menard's edit and write are MCP tools, which the Write/Edit path rules
  # never match, so a PreToolUse hook (./menard-scope.sh) allows them inside those worktrees and
  # leaves every other path to the prompt. Not allowed: answer_proposal, which
  # babylon refuses a Claude anyway, pushes, and deletes.
  home.activation.claudeSessionHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    allow='${builtins.toJSON allowRules}'
    cfg="$HOME/.claude/settings.json"
    record="$HOME/.claude/.ficciones-allow.json"
    prev='[]'
    [ -f "$record" ] && prev=$(cat "$record")
    dead='["Write(~/projects/*/.worktrees/**)","Write(~/.cache/babylon/work/**)"]'
    arena="$HOME/projects/arena"
    has_arena=false
    [ -f "$arena/hooks/hooks.json" ] && has_arena=true
    [ -f "$cfg" ] || { run mkdir -p "$HOME/.claude"; run sh -c 'echo "{}" > "$1"' _ "$cfg"; }
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile sessions ${sessionHooks} --arg arena "$arena" --argjson allow "$allow" --argjson prev "$prev" --argjson dead "$dead" --argjson has_arena "$has_arena" '.env += {
           GIT_EDITOR: "true", PAGER: "cat", GIT_PAGER: "cat", MANPAGER: "cat",
           GIT_TERMINAL_PROMPT: "0" }
         | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
             | map(select(. != "" and . != $arena)) + (if $has_arena then [$arena] else [] end) | join(":"))
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
