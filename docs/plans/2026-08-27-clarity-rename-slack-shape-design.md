# Clarity rename + Slack-shape reshape

2026-08-27. Validated with Andrew section-by-section.

## What this is

The product, stated plainly: **a communication, planning, tracking, and coordination
surface for your agents** — local, Claude Code, pi, whatever. A harness for your
harness. Slack for the crew, with the OpenExecutive SDLC discipline at the helm.

That sentence is the naming machine: for every entity, ask "what would Slack or
Linear call this?" If the answer is obvious, the cute name loses.

## Evidence (god-view of the 2026-08-27 19:21→03:13 session)

- **The SDLC machinery was bypassed entirely.** Real work (3 shipped slices) ran on
  a raw chat thread: `stage = NULL`, zero events, zero todos, zero recorded checks
  despite "368/368 green" claimed three times in prose. Two parallel ways to do
  work exist and the frictionless one wins.
- **The session's own content was a visibility complaint** ("i was about to give up
  for real") — confirmed live, partially fixed in-session (ticking elapsed,
  heartbeat).
- **Referential integrity is already broken**: thread 3 → `world_id = 5`; the world
  table has one row (id 1). Reseeds drift silently; nothing enforces or displays
  membership.
- What worked: memory pass banked good facts; reply→wake ran clean; mid-turn scope
  additions absorbed fine. The bones are good.

## Naming rule

**A name may be cute only if it names something with a personality.** Everything
that is a thing gets called what it is.

Stays (the 5–15%): the repo name `ficciones`; crew personal names (hronir,
tertius — coworkers have names; operator-editable anyway). The `-machine` suffix
dies. The unbuilt Borges env modules in the README (congress, senderos, zahir,
compass) are deleted from the map.

| Now | Becomes |
|---|---|
| world | **workspace** |
| Orbis (space) | **Home** (collapses into the sidebar top) |
| Tlön (space) | *(none — it's just the `ficciones` workspace)* |
| thread / leaf / workline | **thread** (one noun; *tracked* = stage non-null; leaves = parented threads) |
| dossier / "IN SCOPE" | **brief** |
| floor | **pinned** |
| north_star | **goal** |
| chatter | **recent** |
| Chorus / Pulse / "IN FLIGHT" | **Overview / ticker / active** |
| uqbar (tab) | **#general** |
| uqbar (launcher) | the product name (TBD, one-line rename) |
| funes / aleph / manos | **server / console / adapters** (working names) |

Stage names (`intent→spec→plan→build→verify→review→merged`) and the verb-noun MCP
tools (`post_message`, `bank_fact`, `advance_stage`, `record_check`, …) already
pass the rule and stay.

## Structure: five CRUD nouns

1. **Workspace** — paths + roster + knobs. Created/edited/deleted from Home (the
   half-built NEW WORLD modal becomes the real path; the flake seed dies).
   `thread.workspace_id` becomes real, enforced membership; migration repairs
   dangling rows; Home rollup groups by actual membership.
2. **Thread** — the one work/conversation object; optionally tracked (stage).
   Child threads are threads with a parent.
3. **Agent** — archetype + name + engine; roster rows, editable in place.
4. **Session** — an agent's live run on a thread; presence/heartbeat hangs here.
5. **Memory** — facts (with pinned subset) + habits.

Messages, todos, checks, questions, issues, events are line items on threads.

**Tracking is the lazy path**: when a builder lands its first commit on an
untracked thread, the thread auto-promotes to tracked at `build`, backfilled; its
checks start gating advance. The ticket condenses out of the work — no ceremony.
The commit hook fences are the promotion point (already plumbed).

Also killed: the hardcoded `tlon_space/0` fallback and `@fallback_world` twin —
replaced by seed-on-first-boot (also fixes the two-DB "no coworker staffed" seam).

## UI: three columns fed by read-models

The middle seam is three read-models — sidebar rollup, thread view, brief. They
are the contract between server and console; twelve panels collapse into:

- **Left sidebar** (absorbs SPACES, ORBIS/Chorus, TRIAGE, LEAVES, WORKLINES,
  IN FLIGHT): workspaces with open/working counts (Home = the collapsed state);
  per workspace its threads — `●` unread, `⋯ working 3m12s`, stage chip
  (`▸ build`) when tracked; then crew with presence. Triage's unassigned becomes
  an **Inbox** section at top.
- **Center** (absorbs Terminal/WindowBar/Conversation/machine-chat tabs): the
  selected thread with a `[chat] [terminal]` toggle — conversation + composer, or
  the live PTY of whoever's working it. The terminal is reached *through the
  thread* (fixes the "who am I talking to" decoupling). The one-line **ticker**
  stays under center.
- **Right rail** (absorbs Dossier, STACK, MEMORY, HEALTH): contextual — thread
  selected → brief (goal, stage + gate, checks, todos, recent facts); workspace
  selected → branch/commits + pinned memory. HEALTH demotes to a one-line footer
  + `/status`.

Test for any surviving surface: "what question does this answer while I work?"

## Landing order

Behavior first, renames last:

- **A. Integrity + seed** — enforced workspace FK + repair migration +
  seed-on-first-boot. Prereq: merge `worklines` to main.
- **B. Thread unification** — auto-promote on first commit; leaves as parented
  threads; "workline" noun deleted internally.
- **C. Read-models** — sidebar rollup / thread view / brief, server-side,
  tested before UI.
- **D. UI rebuild** — three columns on the read-models; old panels deleted.
- **E. Surface rename** — labels, domain nouns, CLI; MCP tools alias old names
  for one transition window; agent prompts + `funes.eval` steering suite update
  in the same slice.
- **F. Module rename** — `server/console/adapters` + flake/home-manager/launchers
  + memory docs. Zero behavior, biggest blast radius, dead last. Launcher takes
  the product name.

Each slice test-first; `home:switch` green before "done."
