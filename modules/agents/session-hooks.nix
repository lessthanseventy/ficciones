# Claude Code's hooks keeping each session's record in $XDG_RUNTIME_DIR/sessions, which the
# desktop shell reads, and the pane option arena marks windows by (./session-state.sh). Merged
# into settings.json, which Claude Code rewrites: they replace any earlier copy of themselves
# (and the inline arena hooks they grew from) and leave every other hook be.
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
  home.activation.claudeSessionHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$HOME/.claude/settings.json"
    if [ -f "$cfg" ]; then
      tmp=$(mktemp)
      if ${pkgs.jq}/bin/jq --slurpfile sessions ${sessionHooks} '.hooks = reduce ($sessions[0] | to_entries[]) as $e (.hooks // {};
           .[$e.key] = [(.[$e.key] // [])[] | select(tostring | test("@arena_claude|-session-state ") | not)] + $e.value)' "$cfg" > "$tmp"; then
        run chmod 600 "$tmp"
        run mv -f "$tmp" "$cfg"
      else
        rm -f "$tmp"
      fi
    fi
  '';
}
