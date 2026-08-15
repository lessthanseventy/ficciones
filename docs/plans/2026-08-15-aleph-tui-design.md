# aleph — the cockpit, settled: frame, framework, arbiter, and the first board

Written 2026-08-15, in the design session that opened the TUI phase. This **closes the four decisions**
the kickoff note left open (`2026-08-15-aleph-tui-kickoff.md`) and **refines** the cockpit design
(`2026-08-14-aleph-cockpit-and-elixir-spine.md` §1, §5, §7) where the shape moved under it. It does not
supersede the spec (`../../modules/funes/docs/spec.md`) — every rule there still wins. Read those first;
this only records what the session settled and, as loudly, the turns it *rejected* so they do not recur.

The architecture from the kickoff holds — **aleph = the face, an arbiter = the hands, funes = the
memory** — but the session sharpened *how the face is composed*, and that changed which pieces we pull
together. The headline: **aleph is one raxol app whose sidebars are components and whose middle
column is an embedded terminal view of a tmux client. tmux stays the multiplexer; nothing is
reinvented.**

**Spike addendum (2026-08-15, same day).** Standing up `modules/aleph/` corrected two package facts in
the sections below. `raxol_core` is **infrastructure only** (events, config, focus, plugins) — the
renderer is **`raxol_terminal`** (screen buffers + ANSI/VT + the bundled **termbox2 NIF**, which
compiles clean on this box). And because `raxol_terminal` also ships a VT **Emulator**, the
center-column embed likely stays in that one family, making **`ghostty_ex` a fallback rather than a
required dependency** (confirm the child-embed at the step-2 spike). OTP was bumped to **28** (funes
re-proven green, 92 tests); the read-only render path is green (3 headless tests, commit `000cb5c`).
The architecture is unchanged — only the package names under it.

---

## 1 · The stack, one line per layer

Everything the cockpit is, and whose job each piece does. Every piece already exists; the only thing we
build is aleph.

| Layer | Piece | Its one job | Reinvented? |
|---|---|---|---|
| Outer window | **ghostty** | the terminal we render into; top-level windowing/tabs of the app itself | no — it's the daily driver |
| The cockpit | **aleph** (`modules/aleph/`) | one `raxol_core`+`raxol_terminal` app: the 25/50/25 canvas, sidebars-as-components, focus + keymap | **this is the only build** |
| Center engine | **`raxol_terminal` Emulator** (`ghostty_ex` fallback) | render the middle column: parse a tmux client's bytes → cell grid; forward keys | no — bundled with the renderer |
| Multiplexer | **tmux** | spawn / persist / send-keys / capture the real agent sessions | **no — it stays the substrate** |
| Memory | **funes** | the truth: reads, typed events, opaque refs, liveness asked live | already built + green |
| The seam | **`Funes.Arbiter` → tmux** | `wake` = `send-keys`, liveness = `list-panes` / `capture-pane` | tiny adapter, already stubbed |

Register (`aleph-cockpit` §6b): module names are Borges (`aleph`), the daily surface labels stay
corporate-deadpan (`IN SCOPE`, `IN FLIGHT`), and the machine-truth nouns are plain (`panel`, `view`,
`pane_ref`). `harness`, `arbiter`, `engine`, `tmux` are machine-truth and get plain nouns.

---

## 2 · The frame — the one distinction that must never get muddled again

This section exists because the session muddled it twice before it came clear, and the confusion is the
natural one. State it so it cannot regrow.

**There is no free lunch between "sidebars as components" and "tmux paints the middle."** A single TUI
app owns its whole terminal surface; another program cannot paint a live pane *inside* that surface. So:

- If the sidebars are **components in one app** (what we want), then aleph owns the entire canvas and the
  middle is **embedded** into it — a terminal *widget*, not a foreign pane.
- If **tmux composites the whole screen** instead, then left / middle / right are three separate
  panes/processes, and the sidebars are **not** components of one app.

We chose the first. The reconciliation that keeps tmux anyway: **the middle is a `ghostty_ex` terminal
widget, and inside that widget runs a `tmux` client** (`tmux attach` to the focused session).

- Sidebars = panels/components in one `raxol_core` app. ✓
- Middle = one region of that same canvas; `ghostty_ex` renders it (`cells/1` → blit into the middle
  50%; keystrokes when focused → `write/2`). ✓
- **tmux is still the multiplexer** — it spawns, persists, sends keys, captures. `ghostty_ex` only
  *renders a view* of a tmux client. ✓

**The line that was muddled, stated once:** *"aleph spawns and owns the sessions itself, no tmux"* is
reinventing the multiplexer, and is **rejected** (§10). *"tmux multiplexes; aleph embeds a tmux-client
view via `ghostty_ex`"* is just rendering a pane, and is **the design**. Embedding a terminal *view* is
not owning a terminal *substrate*.

---

## 3 · The TUI layer — raxol_core, panels as components, views as data

**Framework: `raxol_core` + `raxol_terminal`** — the disciplined subset of the Raxol family.
`raxol_core` is **infrastructure** (events, config, focus, plugins — *no* renderer); **`raxol_terminal`
is the renderer**: screen buffers, ANSI/VT parsing, input, a VT Emulator, and the bundled **termbox2
NIF** driver. We **leave the full `raxol` umbrella uninstalled** — clustering, CRDTs, time-travel,
payments/mcp/sensor. That is the §8 ex_cortex cut ("take the patterns, leave the weight") applied to a
dependency: take the buffer + driver, leave the data-center.

**A panel is a component; a view is a composition of panels; nothing is a prebaked full-screen
template.** Banked as an owner instruction: *"liveview components, not huge template blocks we're
prebaking."* The minimal day-one form, kept small on purpose:

- `Aleph.Panel` — a tiny behaviour, three callbacks: `read/1` (which funes function), `topics/1` (what
  to subscribe to), `render/1` (cells from the read result). A panel is a **thin view over a funes read
  model** and holds no logic of its own — the kickoff's "keep the render layer thin" rule made into a
  contract.
- Concrete panels are the units: `RosterPanel`, `ThreadListPanel`, `DossierPanel`, and later
  `SessionPanel` (the middle widget).
- A **view is plain data** composing them. The default `cockpit` view:
  `left: [Roster, ThreadList] · center: SessionPanel · right: [Dossier]`.

**Why this shape earns its keep:** it is `aleph-cockpit` §7 ("TUI now, GUI later for free") pushed down
to the component. Because a panel is a pure function of `(a funes read, its topic events) → cells`, the
*same* panel renders in the TUI (`raxol_core`) and, later, in the browser (`raxol_liveview`) over the
same funes contexts. Different "workspace types" showing different sidebars become different
*compositions*, and "configurable" becomes that composition turning into user config.

**Deferred, on purpose:** user-configurable views, a panel registry, per-purpose layouts. We design
*toward* them (the composition is already data) and ship one hardcoded view.

**Naming (§3 discipline):** the composable-layout concept is a **view** (§7 already calls a front-end
"a view over the contexts") — *not* "workspace," which Herdr owns, nor "thread," which funes owns.
So: **panel** (component) + **view** (composition). This avoids the exact collision the spec keeps
getting burned by (the owner asked about naming four separate times; it is load-bearing).

---

## 4 · The center — raxol_terminal's Emulator renders a tmux client (ghostty_ex fallback)

**Primary plan (from the spike): `raxol_terminal`'s own VT `Emulator`.** Since the renderer already
bundles a full VT100 emulator + screen buffer, the center column can feed a tmux client's PTY bytes into
a `raxol_terminal` emulator instance and read cells back for the middle region — no extra native
dependency, one family. The two older payoffs survive the swap: the **web surface** comes via
`raxol_liveview` (§3/§7), and **agent-briefing-from-screen** (aleph §3b) via the emulator's readable
screen buffer / session serialization. The **step-2 spike** must confirm the emulator can be driven as
an *embedded child* (arbitrary PTY stream in, sub-region cells out) rather than only emulating aleph's
own terminal; if it cannot, fall back to `ghostty_ex`.

**Fallback: `ghostty_ex`**, which wraps **libghostty-vt**, Ghostty's own VT engine, as a Zig NIF on the
BEAM. It is the
right embedding layer for two reasons the session verified: libghostty's *embedding GUI ABI* is
explicitly unstable in 2026, but **libghostty-vt (the parse/state half) is the piece Ghostty stabilized
first** — and that is exactly what this binds. And its API is the center-column contract with no
adaptation:

- `Ghostty.Terminal.write/2` — feed the tmux client's PTY bytes in
- `Ghostty.Terminal.cells/1` — read the screen back as a cell grid (grapheme + color + flags) → blit
  into the middle 50%
- `Ghostty.Terminal.snapshot/2` — extract the screen as plain text **or HTML**
- GenServer-based, supervision-friendly; examples already cover PTY integration + LiveView rendering

`snapshot/2` is the sleeper feature, and it pays two of the design's older debts:

1. **The agent-briefing thesis (aleph §3b), realized.** "Brief a session from structured state, never
   the raw transcript" becomes `snapshot(:text)` of a session's actual screen. Ghostty's own tagline —
   "structured access to terminal state for agents and humans alike" — is the funes thesis in another
   voice.
2. **The web surface (§7) for near-free.** `snapshot(:html)` lets `raxol_liveview` show the *real
   session screen* in a browser later, not just the board.

**The one string attached: `ghostty_ex` needs OTP 28**, and it is a Zig NIF (precompiled binaries ship
for x86_64 Linux, so no Zig toolchain on this box). funes runs on **OTP 27** today; the bump is low-risk
(Ecto, PubSub, Elixir 1.19 all support 28) and **lands at step 2, when the center actually needs it** —
proven by re-running the green gate, never assumed. Slice 1 does not need it.

---

## 5 · The arbiter — verbs, a swappable backend, and the deleted mirror

The arbiter is a **capability, not a product** (§8), and funes already has the seam: `Funes.Arbiter`, a
behaviour that defaults to `Inert` and names no tool. This design keeps it and fills it in.

**The backend is tmux.** The verbs the cockpit needs — spawn a session in a pane, send text, read a
pane, focus, list/liveness — map onto tmux (`new-session` / `split-window`, `send-keys`,
`capture-pane`, `select-pane`, `list-panes`). ghostty's native splits are deliberately *not*
programmatically addressable on Linux (Hashimoto scoped multiplexing out of ghostty on purpose; its
scripting is macOS-only AppleScript), and `cmux` — the ghostty-native agent multiplexer — is macOS.
So on this box tmux is the substrate, running *inside* ghostty, viewed through the `ghostty_ex` widget.
Other backends (a future fast multiplexer, a ghostty IPC fork) remain adapters behind the same
behaviour — that is what the seam is *for* (§8c: same design, different config per machine).

**Herdr is thrown away — and Herdr ≠ tmux.** Herdr was the bespoke *layer* that kept its own mirror of
session/pane state; that mirror is what drifted from the ledger in v1. tmux is the dumb, reliable
substrate underneath it. We drop the layer, keep the substrate.

**The mirror is deleted — the load-bearing invariant.** The v1 sync pain was not that a multiplexer
existed; it was that funes *cached its properties* (labels, pane lists, status) and they drifted (§2,
§10: "no mirrored Herdr state"; "when two things answer the same question, delete one"). So, verbatim
from the spec and non-negotiable here:

> funes stores an **opaque `pane_ref`** on a session — never a cached copy of the pane's properties —
> and **liveness is asked of the arbiter live, within the turn that needs it.**

There is no aleph-side mirror either: the arbiter reads tmux at the point of use and caches nothing past
the turn. A cockpit that stores "which panes exist" has already broken this.

**Two verbs, two safety classes** (the kickoff slightly conflated them):

- **Hop-into / focus** — human-initiated, *safe*, **ungated**: the human choosing to enter a pane burns
  nothing. This is the first useful arbiter action after the read-only board.
- **Auto-wake** — switchboard-initiated on delivery (`send-keys`), the one that can burn a five-hour
  window. It stays behind the **engine-credit presence gate** (aleph §3b); the default stays `Inert`
  until that lands. tmux's `list-panes` + funes' warmth window (`last_active_at`, cold past ~1h) already
  supply most of presence; the still-missing half is engine credit/rate-limit, which is engine-specific.

---

## 6 · Where aleph lives, and the dev loop

**Its own `modules/aleph/` mix project**, with `{:funes, path: "../funes"}` — *not* an umbrella, *not*
inside funes. The reason is load-bearing: it keeps funes' dependency list **pristine** (Ecto + PubSub
only) while aleph's TUI deps (`raxol_core`, `termbox2`, later `ghostty_ex`) stay quarantined in aleph.
aleph depends on funes and boots its OTP app to subscribe; **funes never knows aleph exists** (§8
boundary — the same `funes` travels to other machines sovereign). A module is born when it has content
(root `AGENTS.md`): the read-only board is real content, so `modules/aleph/` is created the moment we
build it, not as an empty placeholder before.

**The dev loop stays the one shared control loop.** Root `mise.toml` gains `aleph:run` / `aleph:check` /
`aleph:test` mirroring `funes:*`; the human and any agent drive aleph through the same tasks. The
**first `aleph` task is the spike gate** (§9), because this repo cannot afford a claim that a build works
without having run it.

---

## 7 · Naming — pane_ref, and the reference audit

Banked as an owner instruction: *"make sure everything has the obvious name for what it represents, and
especially pay attention to the things referring to other things."*

**`workspace_ref` → `pane_ref`.** The field was named for **Herdr's** noun ("workspace") when it pointed
into Herdr. Herdr is gone and the ref now points at a **tmux pane** — so the name was lying. Not
`session_ref`: a `session` is the domain row that *runs in* a pane; a session does not reference a
session. The rename touches built, green funes — the `session` schema + migration, the `Funes.Arbiter`
callback, `Funes.Staff`, `Funes.Switchboard`, tests, `spec.md`, `AGENTS.md` — and is done as one change
with a migration, backed by the green gate, not a doc edit alone. It stays **opaque** (§5's invariant).

**The reference audit.** Walk every cross-entity reference and confirm it names what it points at:
`belongs_to :source_session`, `:thread`, `:agent`, the `supersedes` / `taught` / `correlation` edges
(spec "Settled" §5). The rule: a reference is named for its target, never for a tool that happens to own
the target today.

---

## 8 · The first slice — the read-only three-column board

The smallest thing worth looking at, and it renders the two read models that today render nothing.

One `raxol_core` app, the default `cockpit` view, **no arbiter and no middle session yet**:

| Column | Panel(s) | funes read | Re-renders on |
|---|---|---|---|
| **Left 25%** | `RosterPanel` (IN FLIGHT — sessions × agent/thread/warm?) + `ThreadListPanel` | `Staff.roster/0` + thread list | `subscribe_sessions/0`, `subscribe_threads/0` |
| **Center 50%** | `SessionPanel` — a **placeholder** ("session goes here"); the `ghostty_ex`+tmux widget is step 2 | — | — |
| **Right 25%** | `DossierPanel` — the focused thread's IN SCOPE: NORTH STAR / LEARNINGS / BLOCKERS / SHIPPED / CHATTER | `Board.in_scope/1` | `subscribe_thread/1` |

The board's §4 panels distribute cleanly: *what's live / pick what to focus* is the **left**; the *IN
SCOPE dossier* is the **right** ("info about whatever session is in the middle"). The focused thread is
hardcoded for slice 1; **selection** (which introduces the one piece of shared state, the focused-thread
id, and pulls the sidebars under a single brain) is the next increment, not this one.

**Verified by eye, not the green gate.** It is view-only, so the proof is watching it update: the right
column's CHATTER grows as you `Channel.post/1` from another shell; the left roster changes as sessions
start/end. `RUNWAY` / context-% and `ACTION REQUIRED` are **not** in this slice — they need the deferred
`Sense` collectors and a pressure gauge, and inventing a number for them would break "never invent a
duration / a cache that reports an empty world is a lie."

---

## 9 · Build order

1. **The spike gate** (first `aleph` task, before anything is built on it): prove `raxol_core` +
   `termbox2` compiles and paints a box on this box's OTP, and that a `Funes.Bus` event drives an
   `update/2` re-render. If `raxol_core` itself wants OTP 28, that surfaces here.
2. **Slice 1 — the read-only three-column board** (§8): `Aleph.Panel` + the three panels + the `cockpit`
   view, over funes, re-rendering on topics. Verified by eye.
3. **The `pane_ref` rename + reference audit** (§7) in funes — one migration, green gate.
4. **Selection** — pick a thread on the left, the right follows; the sidebars come under one brain.
5. **The center spike (step 2)** — the `ghostty_ex` terminal widget hosting a `tmux` client; OTP 28
   bump lands here; the `Funes.Arbiter` tmux backend (focus first, ungated).
6. **Auto-wake, gated** — the switchboard pokes via tmux `send-keys`, behind the engine-credit presence
   gate; `Inert` remains the default until that gate exists.

Then, earned by evidence: the `raxol_liveview` web surface (via `snapshot(:html)`), configurable views,
the `Sense` collectors and the surfaces they light up.

---

## 10 · Rejected, so it does not recur

Each of these was a live proposal in the session, and each was rejected for a reason worth keeping.

- **Ratatouille** (the kickoff's default framework) — unmaintained since ~2020, built on termbox v1
  (dead upstream) and an `ex_termbox` C NIF whose compile on modern OTP is an unproven risk. `raxol_core`
  is maintained, pure-Elixir, and modular.
- **Full Raxol** — the ex_cortex of TUI frameworks (clustering, CRDTs, time-travel, "agentic
  commerce"). We take `raxol_core` and leave the weight (§3).
- **Drafter** (`jaman/drafter`) — the best *philosophical* fit (LiveView-shaped, NIF-based ANSI, no
  termbox) and the name the cockpit doc used, but it requires OTP 28 and cannot compose *under* raxol as
  a "dashboards on top" layer — two runtimes cannot share one screen. **Parked**, revisit with evidence
  as a possible standalone secondary surface.
- **cmux / ghostty-automator** — the ghostty-native agent multiplexers; `cmux` is macOS, the automator
  is a pinned fork. tmux is the cross-platform substrate here; these stay possible arbiter adapters.
- **aleph hosts its own sessions (ExPTY, no tmux)** — the turn that *was* reinventing the multiplexer
  (persistence, detach/reattach, send-keys, capture). Rejected in favour of "tmux multiplexes; aleph
  embeds a tmux-client view" (§2). The owner's instinct — *"not trying to reinvent the world, just pull
  the right pieces together"* — is the rule this records.
- **Herdr as the arbiter backend** — Herdr is the bespoke mirrored-state layer whose drift the spec was
  written against; thrown away as a *layer* while tmux, the substrate, stays (§5).

---

## 11 · Settled, and by whom

Every decision the kickoff opened now has an answer, and several flipped from the kickoff's defaults on
evidence gathered live in the session.

1. **TUI framework** — `raxol_core` (not Ratatouille), termbox2 I/O, spike-gated. Flipped on the
   framework landscape: Ratatouille is unmaintained; raxol_core is the maintained, disciplined subset.
2. **The frame** — one raxol app, sidebars as components, middle an embedded `ghostty_ex` view of a tmux
   client (§2). The session's real discovery, and the owner's — that "components in one app" and "tmux
   paints the middle" cannot both hold, and the embed reconciles them without reinventing tmux.
3. **Arbiter backend** — tmux, behind the existing `Funes.Arbiter` seam; Herdr thrown away, the mirror
   deleted (§5). The kickoff's "tmux first" survives, but for the sharper reason that tmux is the
   *substrate viewed through the widget*, not merely "the simplest real one."
4. **Where aleph lives** — its own `modules/aleph/` project, funes' deps kept pristine (§6).
5. **The first slice** — the read-only three-column board, verified by eye (§8).

What is left is not a question but work with a gate in front of it: the spike, then the board.
