# Tlön — the operator's view

**The thread is the record.** Every piece of work is a thread on the server: its messages, its
FACTS (with a certainty rank — stated › checked › opinion), its CHECKS (measured exit codes),
TODOS, QUESTIONS, and — since 2026-09-17 — its COMMITS (every commit a coworker makes carries
`Tlon-Thread: <id>`). A coworker joining a thread gets the **brief**: a token-budgeted view of
that record, never a resumed transcript. The brief says so and names the tools that read past
its caps (`get_facts`, `get_messages`, `search_history`).

**Coworkers** are pi or Claude Code sessions the server spawned as citizens of a thread
(`TLON_THREAD`, `TLON_AUTHOR` in their env). They commit only on their thread's `work/<slug>`
branch, in its own worktree (`.worktrees/<slug>`) — the git hooks refuse anything else. A
coworker that goes cold is not resumed; a fresh one is briefed.

**Worklines** are threads with a stage: intent → spec → plan → build → verify → review →
merged. Each stage owes a committed artifact (`work/<slug>/intent.md`, `spec.md`, `plan.md`,
the branch, CHECKS, `review.md`); `advance_stage` refuses without it. Two gates wait on you:
spec → plan and review → merged (`awaiting: andrew`). The shell toasts when a thread starts
waiting; the Neovim sidebar flags it `⚑`.

**From Neovim** (`<leader>oo`): pick a thread → its buffer is the brief plus the conversation;
`c` composes as you (the lead wakes); `t` hosts a coworker on it; `gd` on a COMMITS line opens
the diff; `<leader>gr` reviews a diff with comments, and closing the review posts them into the
thread (`<leader>gR` picks which).

**From a shell:** `mise run server:roster` (who is on the clock), `server:dossier -- <id>`,
`server:post -- <id> <text>`, `server:claude -- <id>` (join a thread as Claude Code),
`workline:verify -- <id> <slug>`.

**Two buckets, not dollars.** Cost here is *which rate-limited subscription am I draining* —
the Claude plan or the ollama plan. Coworkers can ask the other bucket for a second opinion
(`consult_oracle`); the exchange is posted to the thread. `mise run ollama:usage` shows the caps.
