# Changelog

## 0.1.0

First release.

- Verbs that parse the file, change the tree and parse-check what they write, as Sourceror
  patches — only the bytes a verb names move: `outline`, `find`, `deps`, `attr`, `clause`,
  `stmt`, `block`, `module`, `directive`, `rename`, `write`.
- `run`, `inspect` and `diagnostics`: a project's gate, its call graph and a forced compile's
  warnings, each as one structured line.
- `mix menard.mcp`, the same verbs over stdio MCP.
- The Claude Code plugin: a `PreToolUse` hook that blocks `Edit`/`Write` on a module, a
  formatter pass on what is written, and a nudge from a bare `mix test` to `menard run`.
