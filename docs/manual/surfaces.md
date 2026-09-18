# Surfaces

Three surfaces, one brain. Every one reads the same `Server.*` contexts over the same Bus and
wears the same generated palette; none owns state.

| Surface | Where | Day-to-day job | Open it |
|---|---|---|---|
| **asterion** (Neovim) | `~/projects/asterion`, linked at `~/.config/nvim` | code · diffs · review · the Tlön sidebar, thread buffers and composer · a coworker terminal | `nvim`, then `<leader>oo` |
| **console** (TUI) | `modules/console` | the god-view: every thread, coworker, triage, health, ledger at one glance | `tlon` |
| **shell** (astal) | `modules/desktop/shell` | rail, bar, launcher (`>` verbs), deck panes (Agents…), notifications, OSD, lock, theme toggle | always up (`astal-shell.service`) |

The server (`modules/server`, `tlon.service`) is not a surface: it is the record — threads,
facts, checks, todos, worklines — and the MCP channel the coworkers speak. The operator reaches
it from any surface; from a shell, `mise run server:dossier -- <id>` and `server:post`.

**Rule of thumb.** If it is about *one thread's work* (read it, reply, review the diff, watch
the coworker), you are in Neovim. If it is *everything at once*, the console. If it is *the
machine* (volume, workspace, a verb, a toast), the shell.
