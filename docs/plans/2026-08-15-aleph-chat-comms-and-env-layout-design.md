# aleph — the env layout law, and Chat as the comms layer

Written 2026-08-15, in the session that followed the keyhandling polish pass. This **refines** the
cockpit design (`2026-08-15-aleph-tui-design.md` §3/§8, which settled panels-as-components and the
first read-only board) with two things that came clear talking through what the cockpit is *for*:
a **layout law** for the whole environment, and a real shape for **Chat** — the comms layer, now
understood as the primary way the operator talks to agents and starts work. It does not supersede
the spec (`../../modules/funes/docs/spec.md`) — every rule there still wins, and this leans hard on
the fact that the coordination spine (threads + messages + the switchboard) **already exists** in
funes. We are surfacing it, not inventing it.

The one-line headline: **the three-column frame is the whole app; Chat is one mode inside it.** The
env is a meta-shell — a constant switcher plus contextual panels — and Chat is the mode that turns
funes' thread/message spine into a keyboard-total, info-dense comms client.

---

## 1 · The layout law — what is constant, what is contextual

The frame the owner keeps returning to (the "vague general shape of Herdr"), stated so it stops
drifting: the cockpit is **three columns**, and each region has a fixed job in the *shell* even as
its *contents* change per mode.

| Region | Job | Constant or contextual |
|---|---|---|
| **Top-left** | the **switcher** — pick the active mode | **constant** — always there, always the same |
| **Bottom-left** | context *for the mode* — a navigator/index | **contextual** — the mode owns it |
| **Center** | the mode's **main surface** — the thing you're doing | **contextual** — the mode *is* what's here |
| **Right** | context *for whatever the center is focused on* | **contextual** — the mode owns it |

This is not a new mechanism. `Aleph.Workspace` **already** encodes exactly this — a mode is
`%Workspace{surface: {panel, key}, left: [...], right: [...]}` — so "the center is switched, the
bottom-left and right reshape around it" is the struct we have, read correctly. A **mode** (the
switcher's unit, née "workspace") is a *composition*: which panel is the center, and which
situational panels ride in the contextual slots.

**Why the separation matters:** it keeps Chat from swallowing the app. Chat is important — the
primary comms surface — but it is the *communications layer*, not the environment. Terminal (a live
tmux session in the center) and Tickets are peer modes. Getting this line right means the nav model,
the paint layer, and the funes reads are all **env-level** and shared; each mode only supplies a
composition and its own contextual keys.

**Designed toward configurable, shipped simple** (design §3 discipline): the composition is already
data, so user-defined modes are a later config layer, not a rewrite. We ship the hardcoded set.

---

## 2 · The navigation model — vim/lazygit, keyboard-total, modal

Banked as an owner instruction: *"vim/lazygit style nav throughout — at least that mentality."* The
model, and the rule that it is **env-level**, not per-mode:

- **A default navigation mode.** Every action is a single, discoverable key. There is no mouse and no
  persistent text field silently eating keystrokes.
- **Modes you drop into.** Text entry (a chat message, a new thread's title) is an **insert mode**
  entered with a key (`i`), confirmed with `Enter`, abandoned with `Esc` — exactly lazygit's
  commit-message prompt. This generalises the `center_focused?` boolean the cockpit already has: it
  becomes a real `mode` field (§4).
- **Focus moves between panels.** `Tab` (and `h`/`l`) cycle focus among the mode's panels; the
  focused panel is bordered and contributes its **own** contextual keybindings. `j`/`k` navigate
  *within* the focused panel.
- **The keybindings are always shown.** The bottom status bar grows into a context-sensitive hint
  line (the focused panel's verbs), with `?` for a full cheatsheet.

**This lives in `Aleph.Keymap`** — the pure reducer extracted in the keyhandling pass
(`(key, state) → {new_state, effect}`). It gains two dimensions it already half-has: the current
`mode` and the `focused_panel`. Keyhandling stays a pure, fully-tested function of
`(mode, focused_panel, key) → effect`; the Cockpit stays a thin interpreter. The polish pass built
the machine this design fills in.

---

## 3 · Chat mode — the thread manager, not a single conversation

The correction that shaped this doc: **Chat is not *a* chat — it is the series of threads and the
verbs over them.** A **thread is a task-scoped conversation** — "let's review this PR," "implement
this Jira ticket," "research this library and how it fits our stack." It is the operator's unit of
briefing an agent and receiving back, and it is `Funes.Thread` + `Funes.Message` + `Channel.post`,
already durable, already reactive over the Bus. Chat mode is the meta surface that manages them.

Its composition, in the §1 slots:

### Center — the thread series, collapsible

Each thread is one **info-dense line** by default, expanded in place to reveal its conversation and
an inline composer. lazygit folding: `l`/`Enter` expands, `h` collapses; `j`/`k` move between
threads; when expanded, `j`/`k` move between messages.

```
CHAT · 7 threads · 2 need you
▾ ⚡ review PR 329           Carl    2m
    Carl:  pushed the fix, tests are green
    Carl:  anything else on this one?
    you:   _                        [i reply · Esc]
▸ ⚡ implement JIRA-1204     Sandra  14m  · 3 new
▸ ● research raxol embed    Robert  1h   · working
▸ ● triage inbox            Robert  3h
▸ ★ machine-v2 rollout      —       1d
```

The collapsed line surfaces as much as it honestly can: a status glyph, the title, the last
participant, relative time, and a new/working marker. Expanding gives the full history (timestamps,
author colours, scrollback over `Channel.thread_messages`) plus the composer.

### Bottom-left — the smart index (facets that scope the center)

The freed bottom-left is where thread organisation lives — and the best facets are **computed, not
manual**, because funes already knows enough to compute them:

```
VIEWS
 ★ Pinned       2
 ⚡ Needs you    2     ← last message from an agent, unanswered
 ● Active       3     ← warm session / agent working
 ◷ Recent
FOLDERS
 📁 ficciones   5
 📁 excession   2
 + pin a folder
```

Selecting a view scopes the center's thread list. This answers "surface as much as we can, as
intelligently as we can" without inventing state (§5).

### Right — context for the focused thread

IN SCOPE (the dossier that already renders), the thread's participants (from `Staff.roster`),
session status, and the verb menu for what's focused.

---

## 4 · The verbs — thread-level and message-level

Chat mode's contextual keys, split by what they act on. All map onto funes functions that exist or
are small honest additions.

**Thread-level** (focus in the center list or the bottom-left index):

| Key | Verb | funes |
|---|---|---|
| `o` | **open** a new thread — the title prompt is an insert mode | `Channel.open_thread/1` |
| `Enter`/`l` | **focus / expand** a thread | read only |
| `d` | **archive** (close) a thread — history outlives it | `Channel.close_thread/1` |
| `p` | **pin** / unpin | needs a thread attribute (§5) |
| `s` | **open a session** for this thread (spawn/attach tmux) | `Funes.Arbiter` — the ungated hop-into (design §5) |

**Message-level** (a thread is expanded, cursor on a message):

| Key | Verb | funes |
|---|---|---|
| `i` | **compose** a new message to the thread | `Channel.post/1` |
| `r` | **reply** to the message under the cursor — sets `reply_to` | `Channel.post/1` with `reply_to` |

**On "delete old ones":** funes threads **archive**, they do not hard-delete — message history is
durable by design (spec §5b: history outlives the close). `d` = `close_thread`. If a true destructive
delete is ever wanted it is a deliberate spec change, not a UI affordance; archive is the default and
the honest one.

**Identity.** When the operator posts, `author` is a configured operator handle —
`ALEPH_OPERATOR`, defaulting to `andrew` — so agents can address the human by name (one of the
spec's three delivery-targeting paths). It is config, not a mirrored identity row.

---

## 5 · The intelligence, and the funes-honest line

The index facets (§3) are the "intelligent surfacing." The load-bearing rule (spec §10, design §8):
**never invent state; a cache that reports an empty world is a lie.** So each facet is classified by
whether it is computable *today* or needs a small addition — and we ship the computable ones first.

**Computable now — no schema change:**

- **Needs you** — the highest-value signal. A thread whose *last* message was authored by an agent
  (not the operator) and is unanswered → it is waiting on the human. Derivable from `author` +
  message order; `delivered_at` sharpens it. This is the "action required" the board deferred (§8),
  earned honestly from the message stream rather than a mirrored flag.
- **Active** — a thread with a **warm** session. `Staff.roster` already yields `warm?` (via
  `Presence.warm?(last_active_at)`) and `session_for_thread/1`. No new state.
- **Recent** — order by last message id (the true insertion order under funes' single writer, per
  `Channel`'s own note). No new state.

**Needs a small, honest funes addition — staged later:**

- **Pinned** and **Folders (by repo/project)** — `Funes.Thread` today is `title` / `state` /
  `created_at`. Pins and repo-grouping need the thread to *carry* that fact: an optional `pinned`
  flag and a `project` (or `labels`) attribute, with a migration and the green gate — the same
  discipline the `pane_ref` rename followed (design §7), never a doc edit alone. Until then the
  computed views stand on their own.

This staging is the build order's spine: **the computed index is real value with zero schema risk**;
folders/pins land when the thread grows the attribute they need.

---

## 6 · What exists, what we build

Mapping the design onto the tree so the build is additive, not a rewrite.

**Already built (the keyhandling pass + slice-1 board):**

- `Aleph.Keymap` — the pure reducer. Gains `mode` + `focused_panel` (§2).
- `Aleph.Workspace` — the mode/composition struct (`surface`/`left`/`right`) — *is* the §1 layout
  law. Chat mode is one composition.
- `Aleph.Panel.Conversation` — the read-only render (author colours, wrapping). Grows timestamps,
  scrollback, and the collapsible/expanded forms.
- `Aleph.Board` — the paint boundary (now control-byte-safe). Unchanged in shape.
- funes: `Channel.{open_thread,post,close_thread,thread_messages,recent_messages}`, `Message`
  (incl. `reply_to`), `Staff.roster`/`session_for_thread`, the Bus thread/message topics — all
  green today.

**To build (Chat mode):**

1. A **thread-list / navigator** panel (the collapsible center) with expand/collapse + message
   cursor.
2. A **composer** — an insert-mode text buffer panel; `Enter` → `Channel.post`.
3. The **smart index** panel (bottom-left) with the three computed facets (§5).
4. `Aleph.Keymap`: the `mode` (`:nav | :insert`) and `focused_panel` dimensions, the Chat verbs
   (§4), and the panel-focus cycle — all under the existing headless tests.
5. The **hint line** (context-sensitive keybindings) + `?` cheatsheet.

**To build (funes, staged, only when its facet lands):**

6. `thread.pinned` + `thread.project` (migration, green gate) → the Pinned view and Folders.
7. `Funes.Arbiter` tmux backend for `s` (open a session) — the ungated hop-into (design §5/§9.5).

---

## 7 · Build order

1. **`Keymap` modes + panel focus** — promote `center_focused?` to `mode`, add `focused_panel`,
   keep every transition tested headlessly. The nav model before any new panel.
2. **The collapsible thread list** (center) + **timestamps/scrollback** in Conversation — the read
   experience, verified by eye against a seeded db.
3. **The composer** (`i` → insert → `Channel.post`) and **open-thread** (`o`) — the first writes;
   Chat becomes interactive.
4. **`r` reply** (`reply_to`) — flat display with a subtle `↳ re:` marker; nested rendering parked.
5. **The smart index** (Needs-you / Active / Recent) — the computed facets, no schema change.
6. **The hint line + `?`** — discoverability.
7. Then, earned by evidence: `thread.pinned`/`project` → Pinned + Folders; the Arbiter `s` verb; the
   pulled-out full-screen chat surface.

---

## 8 · Parked, so scope stays honest

- **Pulled-out full-screen Chat** — the owner floated Chat "maybe gets pulled out as a special thing
  with its own keybinds." Real, and the mode's own keymap makes it cheap later — but a *focused view*
  is a second composition, not v1. Parked.
- **Nested reply-threading display** — `reply_to` is set in v1 (`r`), but rendering threads as nested
  trees is parked; v1 shows a flat log with a `↳ re:` marker.
- **Hard thread delete** — rejected in favour of archive (§4); history is durable.
- **Repo folders / pins before the schema** — refused: inventing a `project` grouping the thread does
  not carry would be a mirrored lie (§5). It waits for the funes attribute.
- **Unread *counts* as stored state** — the "· 3 new" marker is *computed* from the message stream
  against a last-seen watermark, never a mirrored per-thread counter.

---

## 9 · Settled

1. **The layout law** — constant top-left switcher; contextual bottom-left, center, right; the center
   *is* the mode. It is `Aleph.Workspace` read correctly (§1).
2. **Chat is a mode, not the app** — the comms layer over funes threads, peer to Terminal/Tickets
   (§1/§3).
3. **Nav is vim/lazygit, env-level** — modal (`:nav`/`:insert`), panel-focus, always-shown keys,
   living in the tested `Aleph.Keymap` (§2).
4. **Chat manages a series of threads** — collapsible center, smart index bottom-left, thread context
   right; thread verbs (open/focus/archive/pin/open-session) and message verbs (compose/reply) (§3/§4).
5. **Intelligence is computed, not invented** — Needs-you / Active / Recent ship first with no schema
   change; Pinned / Folders wait for an honest thread attribute (§5).
