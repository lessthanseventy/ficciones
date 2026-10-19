# Cohesion pass and whimsy — a hand-off plan for Sonnet subagents

**Date:** 2026-10-19
**Status:** decided with Andrew 2026-10-19 (§10); built by Fable 5.1 from four read-only audits of ficciones, tlon's office, tlon's server
and adapters, and the live store (58 open tickets, all in the Machine workspace). Nothing here is built.
**Asked:** Andrew: *"go through this whole ficciones/tlon stack and look for improvements/fun/whimsical
things to add. make a plan i can hand off to some sonnet subagents"* and *"a general bug hunt/missing
features pass … be able to scroll windows on a workspace on the top rail like the left rail scrolls
workspaces. things like that. just general cohesion."*

---

## 0 · The call

Cohesion first, whimsy second. The audits found the same shape in every layer: the happy path is rich,
the edges disagree. Eight hand-copied Escape handlers in the shell; a wheel that means workspace on the
rail, brightness on the bar and volume in the tray; a word ("lobby") that is a screen in one hint and a
thread in the next; dials that are stored and read by nothing; a server that generates visitors nobody
sees. Each is small. Together they are the feeling of "good pieces, not cohesive".

So the plan is **five lanes of small tasks**, each one a Sonnet brief with a check, and a **sixth lane
of whimsy** that only proposes what is not already a ticket. Lanes are independent; tasks inside a lane
that touch the same files are ordered.

What this plan does **not** do: re-plan the pieces that are already epics or tickets. Epic #232 (every
stop is a Need) has three children open (#236 tool_denied, #237 pane_stuck, #255 sessions outlive
server:stop); the toy has #58 (cast reacts to events) in flight and ten whimsy tickets filed (§7 lists
them). A subagent given one of those gets the ticket, not a brief from here.

## 1 · How to hand a task off

Every task below is one subagent, **Sonnet**, one branch, one PR. The brief it gets is the task's
block plus these standing lines, verbatim:

- **Repo and law.** `~/projects/ficciones` (read `AGENTS.md`, `modules/desktop/shell/AGENTS.md`) or
  `~/projects/tlon` (read `AGENTS.md` and the module's own: `office/AGENTS.md`, `server/AGENTS.md`,
  `adapters/AGENTS.md`). The four rules in `~/.claude/CLAUDE.md` apply.
- **Where to work.** tlon: `mise run scratch:new -- <slug>` (a worktree under `~/.cache/tlon-scratch/`),
  push `HEAD:refs/heads/<slug>`, open a PR; it lands through `mise run land`. ficciones: a
  `git worktree add ~/.cache/ficciones-wt/<slug>` from main — **never switch branches in the live
  checkout** (its desktop config is out-of-store symlinks; a checkout dangles them). PR against main,
  Andrew lands with `home:switch`.
- **The check is the deliverable.** Each task names its gate. Run it through `scripts/cap.sh`; paste
  the exit line in the PR. tlon's Elixir tests go through `~/projects/menard/bin/menard run test --in
  server`. Edit Elixir with menard verbs, never sed. The shell's gate is `mise run shell:check`
  (bundle + tsc + `shell:test`), never a claim.
- **Never touch the live desktop.** No `wtype`, no `hyprctl dispatch` against Andrew's session, no
  `shell:dev` unless the brief says so. A screenshot (`mise run shot:layer -- bar|rail|deck`) is fine;
  an eyeball pass is Andrew's and the task says so where it needs one.
- **Surgical.** Only the files the task names, plus a test and the doc line the change makes stale
  (same commit). No "while I'm here". If the task turns out bigger than the brief, stop and say so.
- **Commit as who you are.** `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (or the model
  actually running), one commit per step, PR body ends with the usual trailers.
- **File, don't note.** A smell outside the task's scope becomes a ticket (`tlon-cli ticket-file
  <ws> - "<title>" <body>` on the Machine workspace), never an "open:" line in the PR.

Sizes: **S** an hour, **M** an afternoon, **L** a day and probably two PRs. Nothing here is XL; the
XL pieces (§8) are named so nobody starts them by accident.

## 2 · Lane A — the desktop shell (ficciones `modules/desktop/shell`)

The audit's parity table (one line per surface: wheel, click, Esc, click-away, keyboard) is the source.
Every task's gate is `mise run shell:check`; a visual one adds `shot:layer`.

| # | Task | Size |
|---|---|---|
| **A1** | **The bar's window strip scrolls on the wheel.** Andrew's example. `surfaces/Bar.tsx` `Windows()` gets a `Gtk.EventControllerScroll` (VERTICAL) exactly like `Rail.tsx:38-47`: a notch moves focus to the next/previous window in the strip's live left-to-right order (the `clients` computed already sorts by live x), stops at the ends, `dispatch(L.focusWindow(addr))`. Focusing scrolls the layout to the window — that is the point (it is what Super+H/L do). Don't: wrap around; add a wheel to the perf cells. | S |
| **A2** | **One Escape, one `q`.** Eight surfaces hand-roll `keyval === Escape` (Hub:112, Dashboard:174, DocReader:14, Deck:283, Launcher:164, Settings:234, Office:753, Cheatsheet:101). Add `closeKeys(win, {q?: boolean, onEsc?})` to `lib/nav.ts`; each surface calls it. Rule: Esc closes every overlay; `q` also closes an overlay with no text input (Deck, Hub, Dashboard, DocReader, Cheatsheet, Settings); Launcher and Office keep Esc-only (they take text; Office's stepwise Esc stays as `onEsc`). Cheatsheet's any-key-closes stays, declared in its call. Gate: `shell:check` + `grep -rn "Escape" surfaces | wc -l` equals the two declared exceptions. | S |
| **A3** | **One click-away.** Settings has none (Settings.tsx); the others each copy a field (Launcher:191, Deck:333/342, Hub:138, Office:809, Dashboard:197, DocReader:36, Cheatsheet:103) beside the `armClickaway` singleton. Export one `clickawayField()` from `surfaces/Clickaway.tsx`, use it everywhere, give Settings one. `closeOnPress`'s hard-coded class list (`"clock","wx","deck-log"`, Clickaway.tsx:24) becomes a `keep-open` css class set on those cells. Gate: `shell:check`; `grep -rn "GestureClick" surfaces` shows no second field. Order: after A2 (same files). | S |
| **A4** | **Primary button means click.** Every `GestureClick` but two uses `button: 0`, so a right-click on the Aleph toggles the dashboard and closes click-away fields. Make the helper in A3 and `lib/hover.ts` default to `button: 1`; the only any-button gestures are the Backdrop pokes (say so in a one-line comment). Gate: `grep -rn "button: 0" surfaces lib` returns Backdrop only. Order: after A3. | S |
| **A5** | **The wheel has one vocabulary.** Today: rail = workspace, bar battery cell = brightness 5 %, tray volume icon = volume 2 %, nothing elsewhere. Give the Deck's now-playing cell a wheel for volume through the same function the Tray uses (lift it to `lib/sound.ts` or wherever the Tray's stepper lives), and have both steps come from one place. Write the resulting table (surface → wheel does) into `docs/manual/surfaces.md` (it is a hand page; `manual:check` must stay green). Don't: add a wheel to the Office canvas or the Launcher. | S |
| **A6** | **Constants that are settings.** `Rail.tsx:63` hard-codes the Super+hover dwell at 250 ms while the shared helper reads `feel.hoverDwellMs`; the settings plan lists `backdrop.smoothHz` and the cava bar count as still constants. Add the three to `DEFAULTS` in `lib/settings.ts`, read them with `setting()`, add a Settings row each, extend `lib/settings-core.test.mjs`. Update the "Open" paragraph of `docs/plans/2026-10-08-shell-settings-plan.md` (it also still says the hack scale is a constant; it is `backdrop.hackScale`). Gate: `shell:test` + `shell:check`. | S |
| **A7** | **Drifted helpers.** `timeOf` (Notifications.tsx:61), `hhmm` (lib/log.ts:44), a second `hhmm` (panes/Agents.tsx:26); `fmtTurn` (Settings.tsx:92) and `fmtLeft` (lib/timer.ts:26). One `hhmm` and one `duration` in `lib/format.ts`, with a `.test.mjs`. The two unrelated `clean`s get names that say what they strip. Gate: `shell:test`. | S |
| **A8** | **Hover is one setting.** The Rail's workspace strip opens on Super+hover only (250 ms), every other cell opens on click and swaps on slide. Keep both, but the dwell reads `feel.hoverDwellMs` (A6) and the manual's surfaces page says which cells hover and which click. Folds into A6 if the same agent does both. | S |

Eyeball passes that are Andrew's, not an agent's: the Settings menu's clicks and typing (settings plan
"Open"), and A1 on the real bar.

## 3 · Lane B — the office TUI (tlon `office/`)

Gate for every task: `mise run office:check` (bun test at two frozen clocks). A room change re-hashes
goldens with `office:golden` and says so in the commit.

| # | Task | Size |
|---|---|---|
| **B1** | **One key table.** The cohesion plan's Cause 2 fix 6: `office/tui/keys.ts` holds every binding (global, per card, reader, sandbox play keys) with its mode; `detail()` and the foot render from it; `test/keys.test.ts` (which today parses `main.ts` as source) reads the table instead and fails on a collision not declared in it. **Step 1 (this task): no behaviour change** — lift the bindings exactly as they are, declaring today's collisions (`R` reload/review/restart/retry, `S` settings/next crew/save Nina/start ticket/raise cap, `d` docs/dismiss/delete…, `x`, `c`, `f`, `p`) as mode exceptions. Gate: the suite green and `keys.test.ts` asserting the table is the only source (grep `key: "` outside `keys.ts` returns nothing). | M |
| **B2** | **Resolve the collisions.** After B1. Proposal for Andrew to accept or edit, one line each: `R` = reload the TUI only; review becomes `V` (view the branch), restart the server lives in the finder, retry a job is the job card's `⏎`; `S` = settings only; save (Nina, a look) is `⏎` on the card, next crew `>` on the crew screen, start ticket `⏎`, raise cap `+`; `d` = dismiss/delete on anything dismissable, docs become `D` on a thread card (the dump moves to the life card's `⏎`); `x` close-ish, `c` crew/conversation (they do not collide across modes — declare); `f` fire drill (sandbox) vs filter; `p` pet (sandbox) vs pause (finder). The hint `tab crew` vs key `c` is fixed to say `c`. Gate: `keys.test.ts` has no declared exceptions left except the sandbox play keys. | M |
| **B3** | **One word for the screen, one for the thread.** `ctrl+] lobby` names the screen (reader.ts:155, `GLOBALS`, AGENTS.md); the talk design says the room never says "lobby", and `data.ts:40` already renames the standing thread to "the front desk". Decide: the screen is **the room** (`ctrl+] room`), the thread is **the front desk**, a coworker's home window is **at their desk**. Every hint and the AGENTS.md line follow. Gate: `grep -rn "lobby" office/tui office/kit` hits only `talk.ts`'s doc comments about the server's standing thread. | S |
| **B4** | **The `souls` dial does something, the `weirdness` dial does something, or they go.** Both are stored (`kit/whimsy.ts`) and read by nothing (`tui/whimsy-card.ts:28-29` says "not wired yet"). Wire `souls`: off → `kit/company.ts` relations are ignored by `Sim.idleGoal` and the canned seat voices are used; on → today. Wire `weirdness`: `curated` → the door's own six visitors; `procedural` / `invented` → the visitors and puns `Server.ToyPool` already generates reach the room through a new read `GET /api/office/toys/:ws` (a context function + route, per the office law; today only the MCP `glance` tool reads the pool, so a day's generation is never seen). `weirdness` also decides whether the door's visitor pool is the pooled one. Update the toy design §7 line "stored, not yet wired". Gate: `test/whimsy-work-untouched.test.ts` still green; new tests per dial; server `toys` route test. | M |
| **B5** | **The reader's balloon says where the rest is.** Talk design step 1: an overflowing balloon ends `... (v)`, not `...`, so the key that opens the conversation is named. `kit/balloon.ts` / `canvas.ts balloonLines`. Gate: `balloon.test.ts` (the last line's suffix; still ≤ 34 chars). | S |
| **B6** | **The diary credits everyone.** `server/lib/server/diary.ex` credits only `builder` seats, so nolan (QA) and the reviewers never get a diary line. Credit a QA verdict (`submit_qa`), a review (`submit_review`) and a librarian decision too, in the same weekly job. Gate: `diary_test.exs` with one case each. (Server task, listed here because the soul is the office's.) | S |
| **B7** | **Bug hunt by driving.** Not a fix task. Using the `drive-office` skill against `mise run server:dev` + the sandbox, walk every card's listed keys and every board hit and record each that does nothing or does the wrong thing (#177 "clicking a card on the room's board opens nothing" is the known one). Output: one ticket per finding on the Machine workspace, titled `office: <key> on <card> <does what>`, and a PR with nothing but the drive script under `office/test/drive/`. Gate: the tickets exist; the script runs. | M |

## 4 · Lane C — the server and the citizen mod (tlon `server/`, `adapters/`)

Gate: `~/projects/menard/bin/menard run check --in server` (or `mise run server:check`).

| # | Task | Size |
|---|---|---|
| **C1** | **`TLON_OPERATOR` is a handle everywhere.** Cohesion Cause 2 fix 5. `workline.ex` carries the literal `"andrew"` at lines 12, 337, 837, 1030 and 1112 against `Application.get_env(:server, :operator)` elsewhere, so auto-land after grading never fires under another operator name. Replace with the config read; the mod's boolean (`adapters/claude-code/mod.ts:468`, `tasks/claude.toml:29`) becomes `TLON_OPERATOR_MODE=1`, and `TLON_OPERATOR` carries the handle there too. Gate: `grep -rn '"andrew"' server/lib` returns only the seed; one test that grades and lands under `operator: "someone"`. | S |
| **C2** | **The glossary, and the gate that holds it.** Cause 2 fix 1. Write `docs/glossary.md` from the cohesion doc's decided meanings: *lead* vs *tech lead*; *gate* (a stage parked on the operator) vs *the check* (`mise run check`) vs *the release gate*; *bench* vs *crew* vs *the sweep*; *staffing*; *triage*; *schedules* vs *calendar*; *Need*. Then `scripts/check-names.sh` grows a pass: every glossary term's "lives in" column names a module or field that exists, and the retired words in a "never" column (`console`, `cockpit`, `funes` as a product name, `lobby` as a screen) do not appear in `docs/plans/` files dated after today, `AGENTS.md`, or `office/tui`. The renames themselves (`Server.Crew` → `Server.Spawn`) are **not** this task — the glossary records them as pending. Gate: `mise run check:names`. | M |
| **C3** | **One seat status, one renderer.** Cause 2 fix 2. `Server.Coworker.status/1` → `working | waiting | idle | off | cold`, on the snapshot's roster rows; `office/kit/crew.ts` renders it once (glyph + word), and the TUI crew screen, the person card, the mod's `/thread` band, `tlon-cli roster` and the web roster all call that one mapping. `○` then means one thing. Gate: a server test of the enum; a kit test that each surface's string comes from `statusGlyph()`; `grep -rn "●\|○\|◌" office adapters server/lib` hits `crew.ts` only. | M |
| **C4** | **Empty is not truth, part two.** Cause 3 fix 1 is half done: `Tmux.list_windows` returns `{:error, why}` on a tmux fault but still `[]` for a tmux server that is not up (`tmux.ex:82-90`), so every pane prompt resolves "window closed" during a tmux restart. Make "not up" an error too and audit each caller: it either holds its last value and says so or skips the action. Also the `gh` readers in `workline/publish.ex:41-95` (`[]` on error). Gate: a test per caller with tmux down asserting no session ends and no "machine restarted" notice posts. | M |
| **C5** | **`stalled` is its own Need.** `office/needs.ex:15` says `stalled` "has no kind of its own yet". Give it one with its answers (nudge / hand off / close), per the asks-with-answers rule. Gate: the seeded-db Needs test gains the row. | S |
| **C6** | **The life side has a boundary.** `server/AGENTS.md`: "the life side has no privacy boundary yet" — any coworker on a home workspace reads routines, quests and the dump. Assumption to state in the PR: life rows answer only to the operator's own sessions and to seats on that home workspace whose archetype is `assistant`; a dev-workspace seat gets `{:error, :not_yours}`. Gate: an MCP test per life tool under a builder seat. Update the AGENTS.md line. | S |
| **C7** | **The mod's toast and the shell's toast agree.** The citizen mod toasts "landed ✓" with a chime; the shell toasts tlon's info alerts once per key. Make the two read the same alert row (`GET /api/alerts` `info` kind `landed`), so a landing is one event with one wording in both places, and the mod's chime WAV becomes the shell's too (E4). Gate: the alert row's test; a mod test that the toast text is the alert's. | S |

## 5 · Lane D — docs that lie

One Sonnet task, **D1**, surgical, same-commit style: fix each stale line the audits found, nothing
else. Gate: `mise run manual:check` in both repos and a reviewer reading the diff.

- `tlon/office/AGENTS.md`: souls "nothing else consumes it yet" — `kit/company.ts` and `sim.ts` read
  People; say so.
- `tlon/docs/plans/2026-10-06-home-space-and-dollhouse-design.md`: "nothing built" — Life, routines,
  quests, the dump, the viewport, build mode and the tile catalogue are built; add a status table per
  track from the audit (floor: tiles exist but grid offsets are "read but not yet applied", the home is
  a static annex; life: routines/quests/XP/dump built, packs and nags not; dollies: parts, hall, store,
  importer built, outfits and more species not).
- `tlon/docs/plans/2026-10-13-cohesion-off-the-happy-path.md`: "Status: proposed" — Cause 1 is largely
  built (epic #232), Cause 2 is not, Cause 3 is half; put a status line per cause pointing at C1–C5.
- `tlon/docs/plans/2026-10-08-office-as-a-toy-design.md` §8: steps 1, 3, 4, 5 built; 2, 6, 8 partial;
  7 in flight (#58).
- `tlon/docs/plans/2026-10-08-uqbar-design.md`: step 3's TV changelog channel unbuilt (E2), step 5
  is a card not a takeover.
- `ficciones/docs/plans/2026-10-08-shell-settings-plan.md`: hack scale is a setting now (A6 fixes the
  rest).
- `ficciones/docs/plans/2026-09-07-deck-design.md`: "Not done: Tab cycling, keyboard on the log" — done.
- `ficciones/docs/plans/2026-09-17-ficciones-master-plan.md`: already marked superseded; add that the
  console is retired (2026-10-05) so §2's table is read as history.

## 6 · Lane E — whimsy that is not already a ticket

Each is small, each stays on the right side of the one rule (the work is never touched), and each
names what exists so the agent extends rather than re-invents.

| # | Task | Size |
|---|---|---|
| **E1** | **Scharlach's desk.** Toy step 2 gap: his nameplate (*Sheriff (Assistant to the Manager)*) and the WORLD'S BEST SHERIFF mug exist only as rows on his card (`tui/main.ts:1139`). Draw them on his desk in the wide room (`rooms/wide.ts`, a `Scene` prop, `kit/scharlach.ts` supplies the strings), the mug steaming only while he is warm (the kit already fades steam over the warmth window). Gate: golden re-hash + a draw test that the plate is on the sheriff's desk and nobody else's. | S |
| **E2** | **The release on the TV.** Uqbar design step 3: on a cut (`release.sha` changes — the door already detects it for pizza) Uqbar lands on the TV and `kit/tv.ts` gets an interrupt channel that typesets the changelog as an encyclopedia entry (`UQBAR — release 650fa4a. 1. …`), like the LEVEL n channel does, until the next snapshot says the restart is through. The changelog lines come from the snapshot's `release` block (add `notes` there if absent: the cut's commit subjects, server side, `Server.Release`). Gate: `tv.test.ts` renders the channel; a server test for `notes`. | M |
| **E3** | **A wallpaper per palette.** Steals O4, still open: `theme/palettes/<name>.nix` gets a `wallpapers` list and the theme toggle sets one, so uqbar and zahir each have their own sky. `render.nix` + the toggle script, ~20 lines. Gate: `theme:gen`, `theme:contrast`, `flake:check`; the toggle's test. | S |
| **E4** | **The desktop makes a sound.** There is no sfx at all in the shell (`lib/sound.ts` is a detector). Add `lib/sfx.ts`: `play(name)` through `pw-play`, three sounds (a decision alert arrives, a landing, the pomodoro ends), the WAV the citizen mod already ships (`adapters/claude-code/lib/chime.ts`) reused for the landing so the two surfaces chime alike (C7). A setting `sound.sfx` (default on; low vision makes an audible cue worth more than a toast) and a do-not-disturb that mutes it. Gate: `shell:test` for the pure map; by ear is Andrew's. | S |
| **E5** | **Holidays on the canvas.** `Server.Canvas` draws Andrew's GitHub graph from a coworker's post, else the next Life generation, else a date seed — the toy design's "holidays get their picture" is a brief in prose and nothing in code. Add a holiday table as the fallback *before* Life: a pumpkin the week of Oct 31, a tree Dec 18–25, a heart Feb 14, an egg at Easter (computed), fireworks Jan 1, as 52×7 bitmaps in `canvas.ex`'s pure half. Gate: `canvas_test.exs` picks the picture by date. The room already does Oct/Dec; add the Feb 14 corkboard valentine and a New Year's countdown TV channel at 23:50 Dec 31 (`tv.ts`), tests at the frozen clocks. | S |
| **E6** | **Rivals play for blood.** Souls step 4 gap. When `kit/company.ts` says two idle coworkers are rivals and `Sim.idleGoal` sends them to foosball or pool anyway (it avoids pairing, but a table is a table), the game runs longer, the loser's balloon is a sour line from their seat voice, and Scharlach's ledger does **not** tick (it is not work). Gate: `company.test.ts` / `pastimes.test.ts` with a seeded rivalry. | S |
| **E7** | **The clock joke on the desktop.** `office/kit/eggs.ts clockFace` shows `404` at 4:04 and `π` at 3:14 in the room; the rail's clock (`Rail.tsx`) is the plain time. The shell already imports the kit — the rail clock calls `clockFace`. One line and a test. | S |
| **E8** | **A found line in the desktop's Babel.** The office's `babelPage` plants a meaningful line one page in a thousand (`eggs.ts FOUND`); the desktop's Babel backdrop (`lib/babel.ts`, Gutenberg fragments) never does. Share `FOUND` and the odds. | S |
| **E9** | **The stereo's dance trigger is real.** `kit/stereo.ts` says bpm "stays inert until one does" and `bpm()` is a stub returning 140 on a disco. `playerctl metadata xesam:audioBPM` exists for tagged files; read it (desktop side `lib/office.ts` passes `bpm` on the snapshot it already builds from playerctl), fall back to the stub. Pets dance over 120. Gate: `stereo.test.ts`. | S |

## 7 · Already ticketed — give the ticket, not a brief

Open on the Machine workspace, 2026-10-19 (the live store; the service was inactive at audit time, so
read by psql). A subagent assigned one of these starts from the ticket and the design it names.

- Cohesion epic #232: #236 tool_denied Need, #237 pane_stuck Need, #255 sessions outlive server:stop.
  Beside it: #150, #157, #166, #167, #171, #203, #206 (toasts), #246, #251, #253, #254, #273, #312,
  #356, #357, #363 (banter off still spends tokens), #366, #403, #404, #405 (quota 429/402), #406 (high),
  #410, #411, #412.
- Toy and souls: #58 (step 7, in flight), #66 (cast editor), #298 (hall `e`), #290, #323 (side projects
  on the corkboard), #325, #342 (dog slot draws), #140/#401 (saveHome), #217, #358, #368, #393, #394.
- Whimsy already filed: #27 streak photos, #32 home doorbell, #33 seasons, #34 gym, #35 sleep, #36
  visitors from another tlon, #69 Gary the Dumpster Gremlin, #97/#98 parts, #321/#322 pets.
- Uqbar: #151, #161 (the aeroplane, eyeball).
- Search: #258, #259, #260, #305.

## 8 · Too big for this pass — named so nobody starts them by accident

- **The floor as tiles, for real.** `kit/floor.ts` and `kit/tiles.ts` say the grid offset is "read but
  not yet applied"; the home is a static annex with no people. The composed walkable floor with a door
  graph is the dollhouse's track 1 and is a design session, not a brief.
- **`Server.Crew` → `Server.Spawn`** and the other glossary renames (C2 records them).
- **A fish tank / pond / third pet slot**, routine packs, clock-in/clock-out walks: dollhouse tracks
  2–3, after the floor.
- **Hack thumbnails** in the Settings menu (settings plan "Open").

## 9 · Order

Lanes run in parallel, one Sonnet each at most two at a time per repo (the checks queue is one per
machine in tlon). Inside a lane: A2 → A3 → A4; A6 ⊃ A8; B1 → B2 → B3; C1 and C2 first in C; D1 after
B4 and C1 land (it describes them). E7, E8, E3 are the three to hand out first if the point is to see
something fun land today.

## 10 · Decided (Andrew, 2026-10-19)

- **Dispatch:** Sonnet subagents spawned from the planning session, one worktree each, PRs Andrew
  lands. Not through the office's worklines this time.
- **Order:** cohesion first, in lane order; whimsy after.
- **B3:** the screen is **the room** (`ctrl+] room`); the standing thread is **the front desk**; a
  coworker's home window is **at their desk**.
- **B2:** **one meaning per key, strict.** R reload, S settings, d dismiss/delete; review → `V`,
  docs → `D`, save → `⏎` on the card. Hints never need a mode to read.
- **Sandbox play keys** move to **shifted letters** (`D E T F N W P C`) so no card key is shadowed;
  the help line and `playable()` follow, and the README's key list is updated in the same commit.
- **B4:** wire **both** dials: `souls` gates rivalries and soul voices; `weirdness` picks the door's
  curated visitors vs the server's generated pool through a new `GET /api/office/toys/:ws`.
- **C6:** life rows answer to the operator's own sessions and to seats on the home workspace whose
  archetype is `assistant`; every other seat gets `{:error, :not_yours}`.
- **E4:** sound effects **on by default**, silenced by do-not-disturb.
