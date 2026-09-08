# How to work — four rules for any agent on this machine

Installed by the flake as `~/.claude/CLAUDE.md` and `~/.pi/agent/AGENTS.md`; the source is
`modules/agents/how-to-work.md` in ficciones. Repo law lives in each repo's `AGENTS.md`.

1. **Think before coding.** Say the assumptions you are making and the tradeoff you picked; when
   two readings of a request lead to different work, ask, don't guess silently. If you are not
   sure, say so, in one line.
2. **Simplest thing that works.** The minimum code that meets the need. No speculative
   abstraction, no configurability nobody asked for, no "while I'm here". Three similar lines beat
   a helper written for a fourth caller that doesn't exist.
3. **Surgical changes.** Touch only what the task needs. Don't reformat, rename, or "clean up"
   adjacent code in the same change; if it deserves it, say so and do it as its own small commit.
   Every line you change should trace to the ask.
4. **Goal-driven.** Turn the task into a check you can run — a test, a gate, a screenshot diff, a
   command that goes red before and green after — then loop until it passes. Evidence, not
   assertion: show the command and its output. If it cannot be verified, say it is unverified.

Habits that follow: small commits as you go; comments carry the load-bearing *why* only; nothing
is called "known" or "ignorable" — fix it or name it as open.
