# glm worklist — while the Claude window recharges (2026-08-16)

Branch: `dogfood-kitty-keys`. Guardrails, same as ever: branch-only commits, `mise run check`
green before every commit, TDD the pure decision first, thin edges, and **commit as who you
are** (end commit messages with `Co-Authored-By: GLM-5.2 (pi) <noreply@ollama.com>` — new
AGENTS.md rule). Two new walls you may hit, both deliberate: **boundary** (calling a Funes
module that isn't exported by `modules/funes/lib/funes.ex` fails compile — if you truly need a
new export, widening that file is a reviewed one-line diff, say why in the commit) and the
**raxol patch now raises** if its anchors miss (means a dep changed under you — stop and flag).

Ordered by value; each stands alone.

## 1. Smart paste — gather the runtime facts, THEN implement

Goal: the "normal" paste chord does the right thing for text AND images inside aleph
(today: pi expects ctrl+v = image, ctrl+shift+v = text; Andrew always reaches for the
normal chord first and it's wrong for images).

Step 1 — facts (you live inside aleph, so you can measure): temporarily log what
`Aleph.Keymap.handle/2` receives (or read the Driver events) and record, for each of
ctrl+v / ctrl+shift+v / shift+insert pressed in a live center terminal:
does the key event REACH aleph at all (host ghostty may consume ctrl+shift+v as its own
text paste), and with which mods? Write the findings into this file under Step 1.

Step 2 — implement to the facts: a pure `Aleph.Paste.rewrite(key_event, clipboard_mimes)`
(image/* present → the image-paste chord pi expects; else pass through), cockpit edge shells
`wl-paste --list-types` (best-effort; empty on failure → pass through). Platform note for
later, not now: mac = pbpaste/osascript, and cmd+v arrives differently — keep the mime-check
pure so only the edge swaps.
If the facts say host ghostty eats the chord before aleph sees it, STOP after step 1 and
leave the ghostty keybind change to Andrew (machine config is human-owned).

## 2. Screenshot tool for agents (grim/slurp)

New manos tool (pattern: modules/manos/, like the claude-code adapter): a small script +
pi tool/MCP entry so an agent can capture visual state instead of asking Andrew to
screenshot-and-paste. Surface: `screenshot full` | `screenshot region` (slurp) |
`screenshot window` → writes PNG to a temp path, prints the path (agents attach/read it).
Wayland first (grim + slurp are the box's compositors' tools); design the command layer so
macOS (`screencapture`) slots in behind the same verbs. Keep it a dumb capture tool — no
OCR, no diffing. Stretch (discuss in-thread first): a `watch`-style variant that recaptures
on an interval to a stable path, like scripts/watch.sh for eyes.

## 3. Funes: a global "attention" topic (unblocks notifications)

`question_raised` / `issue_raised` broadcast only on per-thread topics, so aleph's new
desktop notifications (Aleph.Notify, OSC 777) miss blockers on unfocused threads. Add ONE
global topic to `Funes.Bus` (name it `attention`) that also carries those two events (and
only those — completions already ride the sessions topic); subscribe the cockpit; test at
the Bus level (broadcast → both topics receive). Spec-touch: none (topics aren't schema).
Bus is already an exported boundary module.

## 4. Prefix-stable briefs (context-reuse crib #1)

See docs/plans/2026-08-16-context-reuse-cribs.md. Deliverable: a test that two consecutive
briefs for an UNCHANGED thread are byte-identical, then fix whatever nondeterminism it
catches (map iteration order, now-relative timestamps, re-worded section headers). Sections
in dossier-vocabulary order, entries in id order, new material appends at section tails.

## 5. Eye-tests to run and report (post findings to the machine thread)

- Tlön = literal tmux now: enter Tlön → tmux status bar, pi in window 0; `^B o` summons the
  claude window (watch its funes registration — author `claude-machine`, thread same as pi's);
  `^B ^B <tmux-prefix>` reaches tmux; mouse clicks switch tmux windows/panes; kill aleph,
  relaunch, the session re-attaches with everything alive.
- The claude window's MCP auth: it connects with a static bearer minted by aleph's node —
  if `/mcp` in that claude shows funes unauthenticated, capture the error verbatim; that's
  the one seam that hasn't been runtime-proven.
- Notifications: from a project session, raise an issue on the FOCUSED thread and check a
  desktop notification appears when the ghostty window is unfocused.

## 6. pi bug: slash commands treated as prose inside aleph

Andrew typed `/clear` in a pi session inside aleph and the MODEL answered ("/clear is a
command, not something I can do") — pi's TUI didn't intercept it. Outside aleph it does.
Reproduce inside aleph, then find what pi's command detection keys on (first-char "/" in an
empty editor? an exact keypress path?) and what arrives differently through aleph's forward
path (the ghostty_key encode). Suspects: the emulator's forced Kitty push changing how "/"
or Enter arrives, or a stray leading byte in the editor. Fix on whichever side is wrong —
if it's pi's, file it against pi with the captured bytes; if it's aleph's encode, TDD via
`Terminal.encode_key/2`.

Also two fresh eye-tests for the newest commits: quit aleph → shell must be CLEAN (type —
no `;5u` garbage; the restore is now belt-and-braces on both screens), and `Ctrl+B 2` /
`Ctrl+B c` must reach tmux in Tlön (aleph's leader moved to Ctrl+Space; the tmux center
spawns with the Kitty push OFF so the prefix flows as \x02). If shift+enter stops working
for pi INSIDE tmux, that's tmux swallowing extended keys — needs `set -s extended-keys on`
in Andrew's tmux config (human-owned; flag it, don't edit).

If something's broken, fix-forward on the branch with the usual gates; if it's ambiguous,
file it on the machine thread and move to the next item.
