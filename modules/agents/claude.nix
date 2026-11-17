# The Claude Code wiring every machine gets, the work Mac too: the hooks keeping each session's
# record in $XDG_RUNTIME_DIR/sessions (./session-state.sh), which the desktop shell reads, and
# `session` with /goal and /brief over them; arena's plugin, whose hooks mark its windows; and the
# shells' env, nothing in which waits on a human. The shell snapshot keeps only PATH, so the env
# cannot live in an rc. No EDITOR: Claude Code's ctrl+g uses it.
# All of it is merged into settings.json, which Claude Code rewrites: the session hooks replace any
# earlier copy of themselves (and the inline arena hooks they grew from) and leave every other hook be.
{ lib, pkgs, ... }:
let
  sessionStateBin = pkgs.writeShellScript "session-state" (
    "PATH=${pkgs.jq}/bin:$PATH\n" + builtins.readFile ./session-state.sh
  );
  sessionState = event: {
    hooks = [
      {
        type = "command";
        command = "${sessionStateBin} ${event}";
      }
    ];
  };
  sessionHooks = pkgs.writeText "session-hooks.json" (
    builtins.toJSON {
      SessionStart = [ (sessionState "start") ];
      UserPromptSubmit = [ (sessionState "prompt") ];
      PostToolUse = [ (sessionState "tool") ];
      Stop = [ (sessionState "stop") ];
      Notification = [
        ((sessionState "waiting") // { matcher = "permission_prompt|elicitation_dialog"; })
      ];
      SessionEnd = [ (sessionState "end") ];
    }
  );
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "session" (
      "PATH=${pkgs.jq}/bin:$PATH\n" + builtins.readFile ./session.sh
    ))
  ];
  home.file.".claude/skills/goal/SKILL.md".source = ./skills/goal/SKILL.md;
  home.file.".claude/skills/brief/SKILL.md".source = ./skills/brief/SKILL.md;

  # arena is a sibling checkout, loaded from where it is so a pull there is the update
  home.activation.claudeSessionHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.claude/settings.json"
    arena="$HOME/projects/arena"
    has_arena=false
    [ -f "$arena/hooks/hooks.json" ] && has_arena=true
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile sessions ${sessionHooks} --arg arena "$arena" --argjson has_arena "$has_arena" '.env += {
           GIT_EDITOR: "true", PAGER: "cat", GIT_PAGER: "cat", MANPAGER: "cat",
           GIT_TERMINAL_PROMPT: "0" }
         | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "") | split(":")
             | map(select(. != "" and . != $arena)) + (if $has_arena then [$arena] else [] end) | join(":"))
         | .hooks = reduce ($sessions[0] | to_entries[]) as $e (.hooks // {};
           .[$e.key] = [(.[$e.key] // [])[] | select(tostring | test("@arena_claude|-session-state ") | not)] + $e.value)' "$cfg" > "$tmp"; then
        run chmod 600 "$tmp"
        run mv -f "$tmp" "$cfg"
      else
        rm -f "$tmp"
      fi
    fi
  '';
}
