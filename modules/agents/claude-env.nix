# The env the Claude Code wiring (./claude.nix) merges into settings.json; nothing in it waits on a human.
{
  GIT_EDITOR = "true";
  PAGER = "cat";
  GIT_PAGER = "cat";
  MANPAGER = "cat";
  GIT_TERMINAL_PROMPT = "0";
  # Auto mode's server-side review holds every built-in file edit, allow rules or not, and its
  # "gave no verdict" is a hard deny that stalls ticket sessions; the local classifier lets the
  # worktree allow rules resolve. Claude Code calls this switch temporary: drop it once the server
  # stops skipping.
  CLAUDE_CODE_AUTO_MODE_SERVER = "0";
}
