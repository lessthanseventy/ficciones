# Tlön — the TUI is the product (2026-09-25)

Supersedes the master plan's surface table (`2026-09-17-ficciones-master-plan.md` §2): Neovim is
dropped ("a too many dabs thought"), the web UI waits. **The console TUI is Tlön's primary
surface**; the shell gets an AI sidebar. The engine (threads, facts, forgetting, staffing) is
sound enough. This plan is about hierarchy and feel.

## Where things stood (measured, not assumed)

- The live store had 9 threads and 15 messages after ~1,300 commits. Now it has 64 imported
  Claude Code conversations (closed, searchable) and 3 live starter threads.
- The core loop works: a post to a thread that has a project → the staffing pass spawns the lead
  in a worktree of that repo within a minute → it replies in the thread (thread #15,
  excessibility, 2026-09-25).
- It broke in ways nobody saw, because nobody used it: the pi adapter had been reading the wrong
  dossier fields, so every pi coworker started with no brief; project-less threads ran in `$HOME`;
  the staffing job failed for 31 hours on a boot-time PATH. All three are fixed.

## The rule: /focus — what lives in the thread and what lives in the terminal

Claude Code's `/focus` shows only the final message; the tool calls stay underneath. Tlön
gets the same split:

| Thread (focus) | Terminal (underneath) |
|---|---|
| the operator's asks | tool calls, diffs as they're written |
| the coworker's answer, one per turn | "running mix test…" |
| decisions, blockers, questions for you | retries, dead ends |
| commits (as COMMITS rows, not prose) | the coworker's own narration |

Presence (thinking / idle, and how long) is the only live signal a thread shows about the work.
Done: heartbeat posts are removed (`15f3b48`). Still open: **auto-track**. A commit promotes the
thread into a workline, and that injects a `▶ BUILD` stage brief, renames the branch mid-task
(`work/t15` → `work/orient-what-is-excessibility`), and gates on artifacts in the *ficciones*
repo whatever the thread's repo is ("branch does not exist", thread #15). Proposal: worklines
become opt-in (the operator's `workline` verb), so a plain thread stays a plain thread.

## The composer: queue vs. now (from Claude Code)

- **Enter queues.** The message goes to the thread at once, and the coworker gets it at its next
  turn boundary, without being interrupted.
- **Ctrl+Enter sends now.** It interrupts the coworker's current turn and delivers.
- The composer shows the queue ("2 queued for hronir"), so it's clear what the coworker hasn't
  seen yet.

## Hierarchy

Workspace ▸ Project (one repo) ▸ Thread. Today the TUI opens threads with no project, so every
new thread lands on ficciones. Needed:

1. New thread → pick a project (default: the last one used), because the project decides where
   the coworker works.
2. Closed threads get a **history** view, since the 64 imported conversations are invisible to
   the TUI right now. Browsing them is how you start: find an old conversation, reopen it or
   spin a new thread off it.
3. The `general` project is ficciones' checkout (the data now says so; the name should too).

## The shell sidebar

The AI popup becomes a full sidebar, separate from notifications. It shows needs-you threads,
a chat pane to answer them in place, and a terminal attached to the selected thread's coworker
that follows the selected project's folder. It reads the same `/api` door the TUI and web will.
Not designed yet: do it after the TUI pass, so the sidebar copies a hierarchy that already works.

## Next

A live pass on the cockpit with Andrew (`mise run console:run:tmux`, drive-cockpit skill): walk
new-thread → reply → review on the starters (#15, #80, #81), and fix what feels wrong in the
order it's felt.
