---
name: brief
description: Brief the user on every Claude session they have running, the ones that are their move first, and hand work between them. Use when the user types /brief, asks what is going on across sessions, or asks this session to coordinate the others.
---

Run `session brief` and show its answer as it is: your move (waiting on an answer, or done and
not yet looked at), running, and parked, each with its goal, next step and what it last did.
Then, in one line, say which to pick up first and why. A session with no goal gets a proposed one,
set only once the user agrees (`session set goal "…" <repo>`).

To hand work to another session: SendMessage to it by the name ListAgents gives (`arena-d6`), and
set its goal or next to match, so the brief tells the same story. Order work that spans repos
here, one message at a time, waiting for each to land before the next that depends on it.
