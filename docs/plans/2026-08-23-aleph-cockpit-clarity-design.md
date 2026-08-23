# Aleph cockpit clarity — movement, layout, footer, selection, images

Date: 2026-08-23 · Status: validated with operator (brainstorm) · Scope: the aleph cockpit
surface (World spaces primarily; Orbis inherits the shared pieces)

## Problem

The cockpit's interaction model is sound but invisible. The operator could not find the CREW
pane (the right column's one-panel-at-a-time carousel has no on-screen trace), the NAV hints
line is stale (`[/]` labeled "space"; it cycles the right panel) and keyed on the literal
`"Tlön"` label (a renamed world gets wrong hints), reaching anything requires managing the
TERM/NAV mode first, and whole boxes advertise dead air (`HABITS (0)`, a right column ~70%
empty). Selection and images have no story, and new Spaces are coming.

## Decisions (operator-validated)

1. **Movement: hybrid, zellij-style.** Keep TERM/NAV (`Ctrl+Space`), but stop making the
   operator manage it: global `Alt+` chords work from ANY mode and switch mode implicitly.
2. **Layout: no dead air, everything addressable.** Border titles with jump digits; Health
   pinned + a visible tabbed carousel; empty sections collapse.
3. **Footer: contextual.** Panels declare their verbs (`hints/1`); the footer shows the verbs
   of the focused pane. The footer is the cheatsheet — no help overlay.
4. **Selection: native + semantic.** Shift+drag (kitty bypasses mouse capture) for arbitrary
   text; `y` yanks the focused item's REAL text via OSC 52.
5. **Images: a kitty-graphics seam** (`Aleph.Graphics`), capability-gated, placeholder
   fallback — groundwork for the coming Spaces; first consumer is the conversation surface.
6. **Rejected (YAGNI):** floating panes (Detail overlay covers it), resize mode (layout is
   deliberately fixed), scroll mode (wheel works), a `?` help modal (footer suffices), pure
   global chords (bare-key browsing in NAV is better), pure modal (the mode tax stays).

## The model

### Movement

- `Alt+1..9` — jump focus to the numbered pane, from anywhere (TERM included); implicitly
  enters NAV. `Alt+0` — focus the center terminal (= TERM mode).
- `Alt+h/j/k/l` — directional pane movement, from anywhere, implicit NAV.
- Global action chords, from anywhere: `Alt+n` new task, `Alt+c` compose, `Alt+[`/`Alt+]`
  cycle the right carousel. Bare `n`/`c`/`[`/`]` keep working in NAV.
- In NAV, bare keys unchanged: `h/l/H/L` walk, `j/k` cursor, Enter detail, Tab sections,
  Esc/`Ctrl+Space` back to TERM.
- **LOCK mode** (zellij's `Ctrl+g` idea): one chord toggles total passthrough — aleph forwards
  EVERYTHING, Alt chords included (readline owns `Alt+digit`/`Alt+f/b`). Footer chip shows
  `LOCK` in a warning color. Unlock = the same chord.

### Layout

- **Border titles**: every box's title moves onto its frame — `┌ 2 STACK ───┐` — digit first.
  The in-content header row + blank die (2 rows back per box). Focused pane: accent + heavy
  frame and title.
- **Numbering** (World spaces): center `0`; left top-down `1 SPACES`, `2 STACK`, `3 MEMORY`;
  right `4 HEALTH`, `5 <carousel>`. Derived from layout order, stable per space.
- **Left column**: unchanged except Memory — an empty section (HABITS with 0 rows) collapses
  to nothing; FLOOR takes the space.
- **Right column**: `4 HEALTH` pinned at intrinsic height (never flexes). Below it the
  carousel at full remaining height: border title is a tab strip — `5 CREW · activity ·
  leaves` — active tab lit, siblings dim, CLICKABLE; `[`/`]` (and `Alt+[`/`]`) cycle. Default
  view: CREW. Dim `[ ] cycle` hint bottom-right of the box.

### Footer (contextual)

`Aleph.Panel` gains an optional callback `hints(data) :: [{keycap, label}]`. Footer = three
segments, clipped right-to-left (mode segment is sacred):

1. **Mode**: `TERM` → `Alt+# panes · ^␣ nav`; `NAV` → `Alt+0 term · q quit`; `LOCK` → the
   unlock chord only.
2. **Space** (NAV, World): `c post · n task · m driver`.
3. **Pane** (NAV): the focused pane's `hints/1` — Stack `j/k commits · ⏎ diff · y sha`,
   Leaves `j/k · ⏎ attach`, Memory `Tab section · j/k · ⏎ open`, carousel slot appends
   `[/] view`. A pane with no verbs declares nothing.

Hints key on `Space.world?/1`, NEVER the space label. The static stale table
(`Panel.StatusBar.@hints` world branch) dies. Compose/new-thread/flash footer clauses stay.

### Selection & yank

- Shift+drag is the universal path (kitty native mouse-capture bypass; tmux copy-mode inside
  the center). Documented once in the footer/README, no code.
- `y` in NAV copies the focused item's semantic text via OSC 52 (works over SSH): commit SHA
  (Stack), message body (conversation/Detail), thread title, fact text (Memory). Declared per
  pane via `hints/1`, implemented per pane next to `pick/3`.

### Images (`Aleph.Graphics`)

- Panels may return **image placements** `{id, source, rect}` alongside rows. After each cell
  paint, placements are emitted as kitty graphics APC sequences: transmit once per id, place
  per frame, delete on scroll/close/resize.
- Capability-gated: kitty detected (env/query) → real images; else a dim `[image WxH]`
  placeholder run. The seam is the deliverable; consumers arrive with the new Spaces.
- First consumer: conversation attachments (pasted image → funes attachment → thumbnail).
- Rider: aleph's tmux servers set `allow-passthrough on` so harnesses inside the center can
  emit kitty graphics themselves.

## Slices (commit per slice; `mise run aleph:check` per slice)

1. **Border titles + digits + Memory collapse** — `Panel.Border` takes
   `%{title, digit, tabs, focused}`; View passes section identity; header rows deleted.
2. **Right column reshape** — Health pinned intrinsic, tabbed carousel below (default CREW),
   tab click switches (extends `pick` routing).
3. **Contextual footer** — `hints/1`, three segments, world-ness keying, stale table deleted.
4. **Global chords + LOCK** — `Alt+digit`/`Alt+hjkl`/`Alt+n·c·[·]`, lock toggle.
   **RISK**: Alt arrives as an ESC prefix; termbox2's `TB_MOD_ALT` should decode it, but the
   cockpit has prior ESC-forwarding surgery (raxol parser patch, `^B` leader, num-lock saga) —
   verify LIVE in kitty before trusting. Fallback needing no new plumbing: leader-digit
   (`^␣ 5`). Slices 1–3 do not depend on this one.
5. **Polish** — heavy accent active frame, `[ ] cycle` corner hint.
6. **Yank** — `y` per pane via OSC 52 + selection documentation.
7. **Graphics seam** — `Aleph.Graphics` + capability gate + tmux `allow-passthrough` +
   conversation thumbnail consumer.

## Testing

Pure throughout: View placement tests (titles/digits/tab strip presence), footer assembly per
mode × focused pane, keymap tests for Alt/lock events and digit jumps, carousel tab `pick`,
graphics placement emission (sequence builders pure; the tty write is the only IO). Live
smoke: one pass through every pane by digit in the real cockpit, shift+drag, a `y` yank, a
thumbnail in kitty + placeholder under a non-kitty TERM.
