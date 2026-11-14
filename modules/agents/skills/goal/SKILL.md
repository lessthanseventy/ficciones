---
name: goal
description: Set what this Claude session is for, and its next step, where /brief and the other sessions read it. Use when the user types /goal, says what a session is for, or names the next step to leave it on.
---

`session set goal "<what this session is for>"` sets this session's goal; `session set next "<the
next step>"` sets where it stands. With the user's words after `/goal`, set the goal to them; with
none, propose one line from the conversation and set it. An empty text clears a field.

When a turn ends with work left that the user has agreed to, set `next` to it, in one line.
`session set next "…" <repo>` sets another session's, by its repo or the start of its id.
