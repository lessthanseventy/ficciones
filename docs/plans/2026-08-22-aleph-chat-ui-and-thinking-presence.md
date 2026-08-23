# Aleph chat UI + thinking-presence — build brief

Date: 2026-08-22 · Lead: builder (hronir/claude-machine) · Root thread: #1 (tertius)

## Goal

Four operator asks on the aleph cockpit chat surface, plus the cross-module spine that makes
"thinking = working" real:

1. Typing/thinking indicators in the cockpit chat — **thinking counts as working**, richest path
   (explicit funes presence events from both harnesses, not just tmux-activity inference).
2. Composer input box grows taller to fit what's typed (wrap + grow, not truncate).
3. Message readability — paragraphs + padding between messages.
4. Operator messages colored differently from agent messages (agents green, operator pink).

## Root causes (already located — don't re-investigate)

- **Typing presence exists only in uqbar.** `Aleph.MachineChat.Presence` (pure, tmux-snapshot-driven)
  derives `:working`/`:live`/`:none` from `window_activity` (content changed within `@working_s`=10s).
  Rendered in machine_chat as `⋯ <lead> is working…` (loop.ex:594-599), `●` glyphs (rail/crew),
  `N working` header. The cockpit's `Panel.Conversation` renders ONLY messages — no signal.
- **Cockpit tabs poll misses activity.** `tlon_tabs` (cockpit.ex ~line 2204) polls
  `tmux list-windows -F "#{window_active}\t#{window_index}\t#{window_name}\t#{@funes_thread}\t#{@funes_opening}"`
  — no `#{window_activity}`.
- **Composer is a 1-line status-bar prompt.** `Panel.StatusBar.render` `:compose` clause
  (status_bar.ex ~line 33) + `cursor_split` (~line 240, keeps ONLY the current line — its own
  comment says "A multiline body's other lines are dropped") + `Panel.clip` truncates to width.
- **Messages are one wrapped block.** `Panel.Conversation.message_rows` (conversation.ex ~line 38)
  and `Aleph.Transcript.message_rows` (transcript.ex ~line 145) render `author: body` word-wrapped
  with a hanging indent — no paragraph breaks, no blank line between messages.
- **No per-author color.** All bodies `:normal` (green `0x33FF00`), all authors `:label` (amber
  `0xFFB000`). Pink already in palette as `:accent` (`0xE0218A`). Operator detection is inline in
  `Funes.Channel.latest_operator_message/1` (channel.ex ~line 200, reads
  `Application.get_env(:funes, :operator, "andrew")`) — not a reusable helper.

## Slices (commit per slice; gate per slice)

### Slice 1 — funes thinking-presence spine
- New `Funes.Presence.Thinking` (in-memory, under funes' OTP supervision tree):
  `%{(thread_id, agent) => started_at}`. API: `thinking(tid, agent)` / `idle(tid, agent)` /
  `thinking_for(tid)` / `thinking_all/0`.
- **Stuck-harness guard:** periodic sweep clears entries older than a configurable max
  (default ~10m) so a crashed harness that never sends `idle` doesn't read as thinking forever.
- New `Funes.Bus` topic `funes:presence` (liveness, like `funes:sessions`). Route
  `{:presence_thinking, %{thread_id, agent, started_at}}` / `{:presence_idle, %{thread_id, agent}}`
  on `funes:presence` + the thread topic. Add to `Funes.Bus` event routing + the `@moduledoc` topic
  list.
- Widen the `Funes` boundary (`lib/funes.ex` exports): export the new module (or delegate
  `thinking_for/1` / `thinking_all/0` on `Funes`). One-line surface widen, reviewed in history.
- MCP tools `presence_thinking` / `presence_idle` — **self-thread** (resolve agent+thread from the
  token, same pattern as `spawn_crew`/`kill_crew`), so a harness emits with no args.
- Headless tests: the store + sweep + Bus routing. Gate: `mise run funes:check`.

### Slice 2 — aleph cockpit: subscribe + render thinking (+ activity floor)
- Subscribe to `funes:presence` once (alongside the activity subscription); keep
  `state.thinking` keyed by thread. Reconcile on (re)connect via `Funes.thinking_all/0`.
- **Lift** `Aleph.MachineChat.Presence` → `Aleph.Presence` (already pure + tmux-snapshot-driven;
  shared now, not machine_chat-private). Update machine_chat call sites.
- Add `#{window_activity}` to `tlon_tabs`' `list-windows -F`; parse it; feed parsed windows into
  `Panel.Conversation` data.
- Render `⋯ <agent> is thinking…` (accent) in `Panel.Conversation` when non-empty. Precedence:
  **thinking > working > live > none** (explicit supersedes tmux-inferred).
- Optional: `⋯` glyph in `Panel.Leaves`/`Panel.ThreadList` and the in-flight `Panel.Roster`.
- Gate: `mise run aleph:check`.

### Slice 3 — aleph: composer grows
- When `state.input.kind == :compose`, `View.compose/3` reserves a growable multi-line box at the
  frame bottom (above the status-bar hints row). Height = wrapped line count, capped at ~half the
  frame height, then scroll.
- Render the FULL buffer wrapped to the column width, `▎` cursor marker on its actual line/col
  (not just the current line). Reuse `Aleph.Text.wrap` per line.
- `Panel.StatusBar` keeps the hints row; the prompt line moves up into the box. The
  `cursor_split` "current line only" assumption goes away.
- Gate: `mise run aleph:check`.

### Slice 4 — aleph: message readability (paragraphs + padding)
- Add a paragraph-aware helper in `Aleph.Text` next to `wrap/2`: split on `\n\n`, wrap each
  paragraph to the width, join with a blank line.
- `Panel.Conversation.message_rows` and `Aleph.Transcript.message_rows`: render paragraphs with the
  hanging indent; one blank row between message blocks (small left margin optional).
- Gate: `mise run aleph:check`.

### Slice 5 — aleph: operator/agent message coloring
- Add a semantic `:operator` style to `Aleph.Style` (pink `0xE0218A`, its own key — NOT reusing
  `:accent`, so a re-theme is one edit and doesn't entangle with the cursor/thinking chrome).
- Add `operator?(author)` (downcase + compare to `Application.get_env(:funes, :operator, "andrew")`)
  on `Funes.Channel` (next to `latest_operator_message`) or an `Aleph.Text` helper; both renderers
  call it.
- In `Panel.Conversation.message_rows`/`author_run` AND `Aleph.Transcript.message_rows`:
  operator-authored → author + body in `:operator` (pink); agent-authored → author `:label`
  (amber) + body `:normal` (green), as today.
- Gate: `mise run aleph:check`.

### Slice 6 — pi emits
- `manos/pi/src/extension.ts`: `turn_start` → emit `presence.thinking` via the `mcp.ts` FunesClient;
  `turn_end` (already exists, refreshes footer) → emit `presence.idle`. Best-effort — a failure
  never disturbs the session (same contract as the rest of the adapter).
- Gate: `mise run manos:pi:check` (`bun test && bun run typecheck`).

### Slice 7 — claude-machine emits
- Add `UserPromptSubmit` hook → `modules/manos/claude-code/thinking-hook.sh` (bun, reuses
  `mcp.ts` FunesClient like `cc-capture.ts`) emits `presence.thinking`.
- `Stop` hook → emit `presence.idle` (fold into `capture-hook.sh` or a parallel hook in
  `launch.sh` settings).
- `SessionEnd` hook → emit `presence.idle` as the exit/crash safety net.
- Wire all three in `launch.sh`'s `settings_json`.
- Gate: `mise run manos:pi:check` (the bun suite covers the shared `mcp.ts`/`capture.ts`).

## Ordering

funes (1) → aleph (2,3,4,5 — may batch as one aleph pass with per-slice commits) → pi (6) →
claude-machine (7). Each slice lands its own gate. Slices 2–5 touch overlapping files
(`Panel.Conversation`, `View.compose`, `Panel.StatusBar`, `Aleph.Style`, `Aleph.Text`,
`Aleph.Transcript`) — coordinate so commits don't conflict.

## Verify (the e2e the operator asked for)

1. `mise run check` (funes + aleph + manos tests + types, all green).
2. `mise run flake:check` (the machine-level gate — flake eval). Do NOT claim done until this runs.
3. **Live e2e smoke:** `mise run aleph:run`, then from a pi coworker (or `mise run funes:console`)
   post to a thread and emit `presence.thinking`. Verify in the cockpit:
   - `⋯ <agent> is thinking…` appears while the harness is thinking and clears on `idle`.
   - Composer: type a long multiline body — it wraps and grows, doesn't truncate.
   - Messages: paragraphs render with blank lines; blank row between messages.
   - Operator messages render pink; agent messages green/amber.
4. Report results to the root thread (#1) so tertius can roll it up.

## Rules (from repo + module AGENTS.md)

- Branch off `main`; commit per slice. Each commit ends with a `Co-Authored-By:` trailer naming the
  model that ACTUALLY wrote it — YOUR model, not a name copied from an example.
- No backticks in `git commit -m "…"` double-quoted messages (bash command substitution).
- Inline comments: load-bearing "why" only — no narrative/devlog. Prose goes in moduledocs /
  AGENTS.md / this plan.
- `funes` boundary is enforced by the `:boundary` compiler — reach past the export list and
  `mise run check` fails. Widen the surface in `lib/funes.ex` on purpose.
- Run git status / clean-tree checks with the sandbox disabled (it injects phantom dotfiles).
- Don't claim "green across every gate" until `mise run flake:check` has actually run.