# Cockpit UX — the principles and the shape (design)

Brainstormed with Andrew 2026-09-08 after the one-brain client split (plan A). His diagnosis:
"the overall UX is muddied — I circled twenty-five approaches to organizing chats, getting in
and out, what displays where. It needs generalized principles: differentiate where it matters,
follow the well-trodden paths everywhere else." The cockpit replaces Claude Code, tmux, cmux,
herdr and a pile of plugins, and ties into the astal shell.

Decisions taken in the conversation: chat is the primary interface (agents and work are what you
drill into from it); the conversation is the middle of the screen with the coworker's terminal
beside it; rails always on, lazygit panes behind a key; Slack navigation plus a fuzzy switcher;
Slack keys outside the terminal, tmux prefix inside it; tickets are their own objects, tied to
threads or not.

## 1. Principles

1. **Copy the habit, differentiate the object.** Layout, navigation and keys come from tools
   people already live in: Slack for conversation, tmux for terminals, lazygit for panes. The
   only things allowed to be novel are the things that are new — a coworker is not a person, a
   session is a thing you can watch, a thread can have a stage. Novelty anywhere else is a tax.
2. **One noun, one place, one verb.** Every object has a single home on screen and a single way
   to create it. Message: the reply box. Thread: the rail. Ticket: the board. Never two doors to
   one action (the rule the verb sprawl broke).
3. **The conversation is the record.** Anything that matters about a session rolls up into its
   thread as a message — permission prompts, questions, completions, failures. The terminal pane
   is for watching, never the only place something can be answered.
4. **Orientation is always on, depth is on demand.** Thin rails you never lose; everything deeper
   in a drawer summoned and dismissed with one key. Same shape as the shell.
5. **Keys follow focus.** Whatever has focus gets the raw keys. Esc steps out of an input into
   letter navigation; a prefix is the exit from a terminal. Only chords are global.
6. **Scope is the workspace.** Everything visible is scoped to the active workspace unless it
   says otherwise; global things say "global".

## 2. The frame

Same anatomy as the shell.

- **Top bar** (one line): active workspace · open thread's title and stage · the coworker on it
  and its warmth · server link state (where "server down" lives).
- **Left rail** (thin, always on): workspaces as a short list; under the active one its
  threads. A thread row = warmth dot · title · at most one badge, by priority: waiting on you >
  unread > working. Slack's sidebar with warmth — the one honest differentiation.
- **Center**: two panes side by side when a session is live, one when not. Left = the
  conversation (messages above, reply box below). Right = the coworker's live terminal
  (libghostty over its tmux window). Tab moves between them. No live session → the conversation
  takes the width and a placeholder row names the verb that starts one.
- **Bottom bar** (one line): key hints for the focused pane + the notice tail (the deck row's
  role in the shell).
- **The drawer** (one key; Esc closes): the lazygit panes — memory, stack, roster, board,
  config, log. Opens over the center, never over the rails; remembers its last pane.

Nothing else. No Home space: rail + top bar is the overview, the board in the drawer is the
rollup.

## 3. Getting around

- **Rail path**: focus the rail, `j`/`k`, Enter opens; `[`/`]` or a number switches workspace
  (tmux windows); Esc from the conversation returns to the rail. Mouse: click a row, click a pane.
- **Switcher**: one chord opens a fuzzy finder over every thread in every workspace, plus
  coworkers (`@`) and tickets (`#`). Enter jumps; a target in another workspace switches it.

**Keys**, three layers:

1. In the reply box: letters type, Enter sends, Esc steps out.
2. Out of an input: letters are commands (lazygit); the bottom bar lists the ones that apply to
   the focused pane; `?` the full sheet; Tab cycles panes; `i`/Enter back into the box.
3. In the terminal pane: every key goes to the coworker. Ctrl+B is the prefix — Ctrl+B Tab
   leaves the pane, Ctrl+B `?` the sheet, Ctrl+B `d` the drawer. tmux, verbatim.

Globals: the switcher and the drawer toggle only (chords; cannot collide). Everything else is
focus-local.

## 4. The data underneath (schema gaps, read against the principles)

- **Tickets** (today: title/body/status/priority/labels/assignee/external mirror/one
  `promoted_thread` link). Add: `ticket_link(from_id, to_id, kind)` with `blocks | relates |
  duplicates | parent` (blocked-by = the inverse read of `blocks`); `ticket_thread(ticket_id,
  thread_id, kind)` many-to-many — a ticket and a thread live independently or tied, both
  directions optional; `promoted_thread` becomes a `promoted` row there. `due_at`, `closed_at`,
  `order` (board column order persists).
- **Threads**: fine as a work item (state, stage, awaiting, parent, workspace, project). Nothing.
- **Messages** (carries principle 3): `kind` (`chat | prompt | question | status`), `payload`
  JSON (options), `resolved_at`, `resolution`. The reply box answers a prompt inline; the
  switchboard routes the answer back to the session.
- **Sessions**: `harness` (pi/claude/codex), `state` (`spawning | warm | cold | ended`) stored,
  `exit_reason`, and `attention` (`working | idle | waiting`) derived the way claude-tmux and
  herdr do it — by pattern-matching the pane text for the harness's input prompt, its permission
  prompt and its interrupt line (per-harness patterns in one module), polled while the session is
  warm. The rail's warmth dot and the "waiting on you" badge read these; a `waiting` transition is
  what rolls a `prompt` message into the thread (principle 3).
- **Workspaces + permissions**: promote out of JSON what the UI shows and edits —
  `workspace_agent(workspace_id, agent_id, role)` (the roster), `workspace_repo(workspace_id,
  path, remote, default_branch)` (paths/repos), and a `policy` table keyed by workspace × agent:
  allowed paths, network, shell, ask-vs-allow default (what the sandbox and permission-system
  seeds encode by hand in the flake today).

## 5. What changes, in what order

**Goes**: the Home space; NAV/TERM as a global mode (becomes "focus is on the terminal pane");
boards as spaces (into the drawer); every second door to posting or creating.

**Slices**, each its own plan, biggest confusion-remover first:

1. **The frame** — rails, two-pane center, drawer; today's lazygit panes move into the drawer
   unchanged. Removes most of the muddiness on its own.
2. **Keys and focus** — the three layers, bottom-bar hints, the switcher; retire the mode switch.
3. **Messages with kinds** — migration; prompts and questions appear in the thread with inline
   answers. Depends on one-brain piece B (sessions in the server) to route answers back.
4. **Tickets done properly** — links, relations, board order; the board view in the drawer with
   the usual columns and blocked badges.
5. **Workspace model** — roster, repos, policies as tables; the drawer's config pane edits them.

**Shell tie-in**: the shell's Tlön cards read the same server; the deck's agents pane shows the
same warmth/awaiting badges as the rail and clicking one focuses the cockpit on that thread.

**Testing**: pure-render tests per pane as today, plus one keymap test per layer asserting which
keys reach which target — focus rules are where regressions hide.

Related: `2026-09-08-tlon-one-brain-umbrella.md` (B feeds slice 3), `2026-09-01-cockpit-homogenize-design.md`
(the previous diagnosis; its Notes-reimagined backlog item stands).
