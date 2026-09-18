# Omarchy + Atlas — what to steal, ranked against what is already here

## North star (Andrew, 2026-09-17)

> ficciones should just be a better Omarchy, with all the Tlön integration it can carry; and
> Tlön should steal every good idea from the bazillion other orchestrators — bring it in line
> with the field, differentiate where it matters and is good, not all over the place.

Two consequences this doc and its successors follow:

1. **ficciones is measured against Omarchy** — the manual, the one-verb-per-action legibility,
   the atomic theme, the update path — and should win on each, with the Tlön surfaces (Agents
   pane, briefs in the shell, the bucket-drain footer) as the part Omarchy cannot have. §2–§3
   below is that measurement; O5 (the manual) and O3 (the verb menu) are the two that close the
   real gaps.
2. **Tlön is measured against the whole orchestrator field, not six tmux managers.** The
   2026-09-08 note "stop surveying" is retired: the field survey is its own research piece
   (`2026-09-17-orchestrator-field-survey.md`, in progress), organised by *mechanism* rather than
   by project — what each one does about the record, the join to git, context assembly, cost,
   attention, sandboxing, review, and rotation — so Tlön adopts the field's baseline where it is
   merely behind and keeps its differentiators (the durable thread as the record; the
   certainty-ranked dossier; the worklines' owed artifacts; one loop for human and agent) where
   they are the point. Differentiate on purpose, not by accident.

## The two sources this doc covers

Andrew surfaced two "points of inspiration": [Omarchy](https://omarchy.org/manual/)
(DHH's omakase Arch + Hyprland distro, 51-chapter manual, `bin/omarchy-*` verbs, atomic themes,
`migrations/`) and [Atlas](https://github.com/pacifio/atlas) (Tauri/Rust desktop cockpit for
coding agents: ACP subprocesses, `.atlas/sessions.db` checkpoints that link commits back to the
session that produced them, shared memory injected into every prompt, `@`-mentions as pointers,
a tokens · calls · $ footer). This doc is the steal-list for both, the gap-list of the astal shell
measured against Omarchy's bar, and the pick for what gets built first.

Sources of truth this ranks against: `AGENTS.md` (the mise loop), `2026-09-08-tlon-one-brain-umbrella.md`
(pieces A–E), `2026-08-27-ai-native-sdlc-workline-design.md` (worklines), `2026-09-02-astal-shell-design.md`,
and the memory note *agent-mission-control-landscape* (six tmux managers already surveyed — this is
NOT a seventh; Atlas is a different class: a durable record, not a pane manager).

---

## 1 · Atlas — the cockpit steals

Atlas's thesis is Tlön's thesis, said differently: *version control records the final diff and
throws the reasoning away; keep the reasoning.* Tlön already keeps it — the thread IS the record
(dossier, FACTS, CHECKS, TODOS, the message tail). What Atlas has that Tlön does not is the **join
between the two records**: from a commit, find the conversation; from a thread, list its commits.

| # | Atlas move | What Tlön has | Verdict |
|---|---|---|---|
| A1 | **Commit ↔ session link**, surviving rebase/amend (patch-id reconciliation) | Worktree per thread (`work/<slug>`, `Server.Worktree`), the owed-artifact check (`Artifacts.Git`), `Console.Stack.commits/2` reading `git log` with no thread awareness. Claude Code already stamps a `Claude-Session:` trailer on its commits. **Nothing joins a commit to a thread.** | **BUILD NOW.** Ficciones-shaped version: a `Tlon-Thread: <id>` trailer, not a patch-id database — trailers ride the message through rebase/amend/cherry-pick for free, and the repo already lives by trailers. Details §3. |
| A2 | **Shared memory injected into every prompt** (decisions/failures from any agent) | `Board.brief/1` → LEARNINGS is the forgetting engine's token-budgeted working set; `get_dossier` on session start (`brief-hook.sh`); the wipe-proof seed + `promote_fact`. | **HAVE, and better** (budgeted + forgetting + certainty ranks). Nothing to take. |
| A3 | **Session handoff on first message** | Rotation = fresh session + dossier catch-up, never `/resume` (WS2 shipped). | HAVE. |
| A4 | **`@`-mentions resolve to pointers, not content** (files/folders/commits/notes/past sessions) | `Server.Mentions` routes `@agent`. No `@file` / `@commit` / `@thread` resolution in the composer. | **LATER, small.** Once A1 lands, `@<sha>` → "commit + its thread" is a natural read; `@#42` → thread brief link. Slot into UX slice 3 (status message kind), not before. |
| A5 | **Timeline module** — activity log, filterable, persistent pins | `Board.recent_activity/1` + NOW row + the Event table (closed kinds, correlation). Pins: none. | HAVE the feed; **pins** are a one-column add (`event.pinned_at`) when the cockpit's NOW row gets a keybind. Not now. |
| A6 | **Block-based terminal** (per-command exit code + duration) | `scripts/cap.sh` does exactly this for the agent's loop (one run, log, signal); the console embeds real PTYs (libghostty). | HAVE, in the shape that fits a TUI. |
| A7 | **Knowledge base as markdown with backlinks** (`.atlas/knowledge/`) | NOTES cards (D4) + `Server.Note`; the "notes-reimagined" backlog (WS5). | Parked with WS5; Atlas confirms the shape (markdown, backlinks, project-scoped). |
| A8 | **tokens · calls · $ footer** | `mise ollama:usage` reads the plan caps; nothing in the cockpit or shell. Tlön's "cost" is *which rate-limited bucket am I draining*, not dollars. | **STEAL THE SLOT, NOT THE UNIT.** The footer should read `claude 5h ▓▓▓░ 62% · ollama ▓░░░ 18%` — bucket drain, per AGENTS.md's own definition. Piece E (Oban) is where the sampler lives; a shell Rail cell can read the same number. |
| A9 | **Secrets scrubbed before persistence** (not just before upload) | `Server.Secrets` exists; `capture-hook.sh` writes transcripts. Unverified whether captured text is scrubbed. | **AUDIT, one hour**: grep `capture-hook.sh` → `Server.Secrets` path; if no scrub on the capture write, add it. |
| A10 | ACP as the agent protocol; multiple harnesses, no per-agent special cases | MCP sovereign channel (`Server.MCP.*`), pi + Claude Code adapters, the harness-detection pattern tables noted for piece B. | HAVE (MCP not ACP; the coworker is a citizen, not a subprocess). Revisit ACP only if a harness we want speaks only ACP. |
| A11 | The **screenshot's frame**: left rail (Timeline · Chat · Members · Modules · Projects), one tab strip, chat as the front door, footer with cost | `2026-08-19` locked decision 3+4 (chat = front door, coworkers roster in the left rail); homogenize pass (rail per workspace). | HAVE the decisions; Atlas is a second data point that the rail-of-modules + chat-centre is right. Nothing to change. |

**Net: one build (A1), one audit (A9), one footer re-definition (A8, parked to E), two "later" reads (A4, A5).**

---

## 2 · Omarchy — the machine steals

Omarchy is a *distribution*; ficciones is a *flake for one machine*. The bar Omarchy sets is not
features — the flake has more — it is **legibility**: every action has a `bin/omarchy-<verb>`
name, every verb is in a menu, every menu is in a manual, and an upgrade is a numbered migration.

| # | Omarchy move | What ficciones has | Verdict |
|---|---|---|---|
| O1 | **`migrations/<timestamp>.sh`** — a versioned, once-only step run on update | `home.activation.*` entries run *every* switch (idempotent by discipline: `hyprlandGitHooks`, `keyringDefault`, the theme-file seed). No once-only, no record of what ran. | **TAKE the record, not the shape.** Nix already makes the *state* declarative; what's missing is the one-off *repair* ("chmod the theme file", "delete the caelestia leftovers"). A `modules/os/migrations/` dir of numbered scripts + a stamp file (`~/.local/state/ficciones/migrated`) run from one activation entry. Small; do it when the next one-off repair appears rather than speculatively. |
| O2 | **One CLI namespace: `omarchy-*`** (theme-set, update, refresh, install, launch…) | `mise run <group>:<verb>` — 60+ tasks in `tasks/*.toml`, discoverable by `mise tasks`. | **HAVE, arguably better** (one loop for human and agent). Do not add a second namespace. |
| O3 | **`omarchy-menu`** — walker-style menu of every verb, keybound | `Launcher.tsx` launches apps. No verb menu; `mise tasks` is terminal-only. | **BUILD, small, after A1**: the launcher gets a `>` prefix mode that lists `mise tasks` (parsed from `mise tasks --json`) and runs the picked one in a ghostty window. Omarchy's single best UX idea, and ~60 lines of TSX on the existing surface. |
| O4 | **Atomic theme switch** across every app + wallpaper set per theme | `~/.config/ficciones/theme` symlink repointed by the toggle; 22 rendered surfaces × 2 palettes; WCAG gate; live-switch for Claude Code/ghostty. | **HAVE, stricter** (contrast gate; role layer). Omarchy's per-theme wallpaper dir is the one thing to lift: `palettes/<name>.nix` gets a `wallpapers` list and the toggle sets one. Cosmetic; a 20-line change in `render.nix` + the toggle script. |
| O5 | **The manual** — 51 chapters, one per hotkey group / app / concept | `docs/plans/` (design docs, ~40), `AGENTS.md` per module, `Cheatsheet.tsx` (live keybind sheet from `hyprland.lua`). No operator-facing manual. | **THE REAL GAP.** Plans say what was decided; nothing says *how to drive the machine today*. Proposal: `docs/manual/` with ≤12 short pages generated where possible (hotkeys FROM hyprland.lua, tasks FROM `mise tasks --json`, palette FROM palette.nix) so it can't drift — the AGENTS.md rule ("a task, never prose that drifts") applied to docs. Rendered by the shell's Cheatsheet as a second tab. Medium; its own slice. |
| O6 | **`omarchy-update`** — one command: pull, migrate, rebuild, restart | `mise flake:bump` + `home:switch` + `shell:restart` + `server:restart` — four commands, in the right order only if you remember it. | **BUILD, trivial**: `mise run machine:update` = the four in order, through `cap`. Ten lines of toml. |
| O7 | Curated app set (Neovim, Chromium, Obsidian, LibreOffice, Kdenlive, OBS, a Winamp) | The flake owns what it owns (`pacman-flake-ownership` memory). | Not comparable; skip. |
| O8 | **Agents/skills shipped with the distro** (`agents/skills/`) | `agents/` at repo root; `.claude/` per module; the how-to-work file. | HAVE. |
| O9 | **"A beautiful system is a motivating system"** as the stated why | The astal design doc's "GUI that feels like a TUI"; the palette law. | Same conviction, opposite taste. Nothing to take but the confidence to write the manual. |

**Net: two trivial builds (O6, O3), one medium slice (O5 — the manual), two parked cosmetics (O1, O4).**

---

## 3 · The shell gap-list (astal shell vs the Omarchy bar)

Measured surface by surface. "Bar" = what Omarchy's manual promises a user; "Have" = what
`modules/desktop/shell` renders today.

| Surface | Omarchy bar | Have | Gap |
|---|---|---|---|
| Bar/rail | Waybar: workspaces, clock, tray, battery, net, audio | `Rail.tsx` + `Bar.tsx`: workspaces, minimap, clock, status-as-text, tray | none |
| Launcher | walker: apps + a verb menu (`omarchy-menu`) keybound to Super+Alt+Space | `Launcher.tsx`: apps | **verb mode (O3)** |
| Notifications | mako, themed | `Notifications.tsx` | none |
| OSD | swayosd volume/brightness | `Osd.tsx` | none |
| Lock | hyprlock, themed per palette | `hyprlock.conf` rendered per palette + `hyprlock:preview` | none (ours has a preview gate) |
| Idle | hypridle | `hypridle.conf`; logind inhibitor in the shell | none |
| Theme switch | `omarchy-theme-set`, per-theme wallpapers, ~10 themes | toggle between 2 palettes, WCAG-gated | **per-theme wallpaper (O4)**; palette count is a choice, not a gap |
| Screenshots | Super+Print regions | `shot:*` tasks (monitor/window/layer/region) | none (ours is more) |
| Clipboard history | cliphist via walker | not in the shell | **missing** — a Launcher mode over `cliphist list`; small. Andrew has not asked; note only. |
| Cheatsheet | Super+K keybinding sheet | `Cheatsheet.tsx` from `hyprland.lua` | none |
| Dashboard/panes | none in Omarchy | `Deck.tsx` + 11 panes incl. `Agents.tsx` | ours has more |
| Update | `omarchy-update` | four tasks | **`machine:update` (O6)** |
| Manual | 51 chapters | none | **O5** |
| Migrations | numbered once-only scripts | every-switch activation | **O1**, on demand |
| Fonts/a11y | none | ComicShannsMono everywhere, AAA contrast gate | ours; not a gap |

---

## 4 · The pick, and what "done" is

Order, by substance-per-effort and by what unblocks what:

1. **A1 — commit ↔ thread link** (this session). Done = a coworker's commit carries
   `Tlon-Thread: N` without the coworker doing anything; `get_dossier` / `server:dossier` /
   the cockpit brief show a COMMITS section for the thread; a rebase does not break the join.
   Gate: `mise run server:test` green with a git-fixture test; a live commit from a
   `server:claude` pane shows in `server:dossier`.
2. **O6 — `machine:update`** (ten lines; next session's first commit).
3. **O3 — launcher verb mode** (a shell slice; ~60 lines, screenshot-verified).
4. **A9 — secrets-on-capture audit** (an hour; either "already scrubbed" or one call).
5. **O5 — the manual**, generated where it can be (its own plan).
6. Parked: A4 `@`-pointers, A5 pins, A8 bucket footer (→ piece E), O1 migrations (on demand),
   O4 per-theme wallpaper.

### A1 design — the trailer, not the database

Atlas reconciles by patch-id because its commits are made by arbitrary agents it does not
control. Tlön controls the pane: every coworker commits from a worktree of a repo whose
`core.hooksPath` is `scripts/git-hooks/` (installed by `home.activation.hyprlandGitHooks`), with
`TLON_THREAD` in its environment (`Server.MCP.Spawn.exports/3`). So:

- **Write side — `scripts/git-hooks/prepare-commit-msg`**: when `TLON_THREAD` is set and the
  message does not already carry the trailer, `git interpret-trailers --in-place
  --trailer "Tlon-Thread: $TLON_THREAD"`. Also `Tlon-Author: $TLON_AUTHOR`. Never fails the
  commit. Hooks live in the common dir, so every worktree of the repo gets it.
- **Read side — `Server.Commits.for_thread/2`**: `git -C <repo_for_thread> log --all
  --grep='^Tlon-Thread: <id>$' --format=<sha>%x1f<subject>%x1f<author>%x1f<iso date>`,
  capped like every other brief section. Best-effort + honest like `Artifacts.Git`: a git fault
  is `{:error, reason}` → an empty section, never a crashed brief.
- **Surface — `Board.brief/1` gains `commits: %{shown, more}`**, `Server.MCP.Brief.scope/1`
  renders it, `adapters/pi/src/brief.ts` prints a COMMITS block (additive: `commits` optional
  on the type so older servers still render).
- **Why trailer beats patch-id here**: a trailer is part of the commit message, and every
  history rewrite git does (rebase, amend, cherry-pick, `--fixup`) carries the message. Patch-id
  is only needed when you can't stamp the message at write time — Tlön can. A commit made by a
  human in a plain terminal has no `TLON_THREAD` and gets no trailer, which is correct: it was
  not a thread's work.
- **Not built**: the reverse lookup from the cockpit's STACK panel (`Console.Stack.commits/2`
  showing the thread beside each commit). It is a `%(trailers:key=Tlon-Thread)` format field
  away once the trailer exists; do it with the STACK panel's next eye-pass.
