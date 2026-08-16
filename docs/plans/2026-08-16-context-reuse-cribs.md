# Context-reuse cribs (from the LMCache write-up on Claude Code)

Source: https://blog.lmcache.ai/en/2025/12/23/context-engineering-reuse-pattern-under-the-hood-of-claude-code/
— Andrew flagged it as worth cribbing for this stack (2026-08-16). The article documents the
patterns behind Claude Code's ~92% prefix reuse: append-only history, summarization boundaries
between phases, role-scoped subagent context, plan checkpoints as cache resets, subagent tool
lists as subsets of the parent's.

Our providers are rate-limited, not per-token, so the win here is **context-window headroom and
latency**, not dollars — a coworker whose brief is stable spends its window on work, not on
re-reading a differently-worded past every session.

## Crib 1 — prefix-stable briefs (funes)

The brief a harness gets on join IS our summarization boundary. Make it **deterministic and
append-shaped**: stable section order (the dossier vocabulary order: FACTS · UNKNOWNS ·
BLOCKERS · TODOS · CHECKS · CHATTER), stable header wording, entries in stable (id) order,
new information appearing at the END of a section rather than reflowing the whole thing.
A rejoin should produce a brief whose PREFIX is byte-identical to the last one, plus new tail.

- [ ] Audit `Funes.Dossier`/the brief tool for nondeterminism (map iteration, "now"-relative
      dates, re-worded summaries) and pin with a test: two consecutive briefs on an unchanged
      thread must be byte-identical.
- [ ] The claude adapter's brief-hook and pi's join brief should share that one generator.

## Crib 2 — scoped briefs for spawned agents (funes MCP.Spawn)

Spawned agents get context scoped to their mandate, not the whole dossier. The `mandate`
argument to `Spawn.env/join` already names the role; the brief should filter on it — a
"machine" coworker gets machine-thread context, a project session gets its thread's dossier,
nobody gets the chorus firehose.

- [ ] `Spawn.join(thread, agent, mandate:)` → brief sections filtered by mandate; default
      unchanged (whole-thread dossier) so nothing breaks.

## Crib 3 — phase checkpoints as reset points (aleph/Tlön)

The recurring machine coworker should APPEND findings to its machine thread (facts, checks,
issues) and re-derive its working context from the thread brief on each wake — not carry a
mutating in-session summary. The thread is the durable prefix; the session is disposable.
This is also the fix for the notification gap below: phase boundaries are where "done /
waiting on you" events get posted.

## Related follow-up — global meta topic for waiting-on-you events (funes Bus)

`question_raised` / `issue_raised` publish only on per-thread topics today, so aleph's new
desktop notifications (OSC 777, `Aleph.Notify`) only see them for the FOCUSED thread.
- [ ] Add a global `questions`/`issues` (or one `attention`) topic to `Funes.Bus` so the
      cockpit can subscribe once and notify for ANY thread's blocker. Bus is an exported
      boundary module; the topic is additive.
