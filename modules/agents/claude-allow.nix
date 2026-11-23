# The permission rules the Claude Code wiring (./claude.nix) merges into settings.json.
let
  board = map (t: "mcp__plugin_arena_babylon__" + t) [
    "claim_ticket"
    "submit_ticket"
    "release_ticket"
    "file_ticket"
    "update_ticket"
    "bump_ticket"
    "link_tickets"
    "unlink_tickets"
    "get_ticket"
    "list_tickets"
    "inbox"
    "propose"
    "list_proposals"
    "answer_ask"
  ];
in
board
++ [
  "Edit(~/projects/*/.worktrees/**)"
  "Edit(~/.cache/babylon/work/**)"
  "mcp__plugin_menard_menard__edit"
  "mcp__plugin_menard_menard__write"
]
