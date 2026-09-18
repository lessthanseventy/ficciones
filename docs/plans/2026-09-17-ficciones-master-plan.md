# ficciones — the one plan (2026-09-17)

Andrew: "let's put all these plans and docs and shit together into one coherent one to follow."
This is that document. It states the north star, names the surfaces, sequences the work, and
points at the detailed docs for each piece. When a piece is built its row here is updated;
nothing below is "done" until its check is green. Plans written far ahead go stale (roadmap
lesson, 2026-09-01), so pieces more than one step out are *named*, not *detailed*.

---

## 0 · North star

> **ficciones is a better Omarchy, with every Tlön integration it can carry.**
> **Tlön steals every good idea from the orchestrator field and differentiates on purpose.**
> **The day-to-day surface is Neovim — a maximal config where Tlön's screens, diffs, terminals,
> notes and project management live. The console TUI becomes the god-view.**

Three surfaces, one brain:

```
                 ┌──────────────── Tlön server (always up, one store) ─────────────────┐
                 │  Server.* contexts · Bus · MCP · Sessions (tmux) · [Postgres] · [Oban]│
                 └───────┬───────────────────┬───────────────────┬─────────────────────┘
                         │ HTTP/MCP (→ erpc)  │ erpc + pg          │ MCP/HTTP
              ┌──────────┴────────┐  ┌────────┴────────┐  ┌───────┴────────┐
              │ NEOVIM (asterion) │  │ console TUI     │  │ astal shell    │
              │ the daily front   │  │ the god-view    │  │ the desktop    │
              │ threads · review  │  │ everything at   │  │ Agents pane ·  │
              │ terminals · notes │  │ once, one glance│  │ notifications ·│
              │ projects · AI     │  │                 │  │ bucket footer  │
              └───────────────────┘  └─────────────────┘  └────────────────┘
                                       coworkers: pi / Claude Code in tmux, per-thread worktrees
```

The rule that keeps three surfaces from becoming three computers: **every surface reads the same
`Server.*` contexts and the same Bus topics, and wears the same generated palette.** No client
owns state. No client names a hue.

## 1 · What is already true (do not rebuild)

- **Server**: threads as the record; FACTS with certainty + forgetting; CHECKS; TODOS/QUESTIONS;
  worklines (gated, artifact-owing stages); per-thread worktrees; MCP channel; seed + fact
  promotion; steering-config evals in CI; one-brain piece A (client split). Today: the
  `Tlon-Thread` commit trailer + COMMITS in every brief (`a2fa10e`, `c08dd11`).
- **Console**: 25 panels (rail, thread stack, composer, crew, triage, tickets kanban, notes,
  stack, terminal, health, menu…), 874 tests, libghostty terminal embedding.
- **Shell**: astal, 13 surfaces + 11 panes, systemd-supervised, WCAG-gated two-palette theme
  across 22 rendered surfaces, live switch, `shot:*` gates.
- **Loop**: `mise` tasks are the one API for human and agent; `cap`; `watch`; menard for Elixir.
  Today: `machine:update` (`807914f`).
- **Field position** (survey §3): the thread-as-record, certainty-ranked facts, artifact-gated
  worklines, dossier-not-transcript, bucket routing and evals-on-steering are validated
  differentiators. Keep them; do not flatten any of them to "match the field".

## 2 · The surfaces and what moves where

| Concern | Today | Target | Why |
|---|---|---|---|
| Read a thread, reply, wake a coworker | console composer panel | **Neovim** thread buffer + composer | modes kill the keymap problem; it is where the code is |
| Review a coworker's work | console stack + lazygit | **Neovim** diff mode, inline comments posted back to the thread | field baseline: nobody reviews in a hand-rolled TUI (survey §1 baseline 5) |
| Watch coworker terminals | console terminal panel (libghostty) | **Neovim** `:terminal` attached to the server's tmux windows; console keeps its embed | "a better tmux than tmux" |
| Roster / attention | console crew + shell Agents pane | Neovim sidebar **and** shell notifications | needs-you must reach you outside any window (survey §4 adopt #2) |
| Tickets, notes, projects | console kanban + note cards | **Neovim** (kanban/notes/project plugins over the same rows) | the editor is where notes are written anyway |
| God-view: every thread, every coworker, triage, health, ledger | console | **console** (unchanged role, fewer duties) | one glance, one window, no editing |
| Desktop status, launcher, OSD, lock, theme switch | shell | shell + **verb menu** + **manual** | the Omarchy bar (steals §2–§3) |

The console does not lose code in this plan; it loses *duties*. Nothing is deleted until
Neovim has carried the duty live for a while.

## 3 · Organisation — name and repo

`menard` was pulled out (2026-09-17) because it is a general tool with its own release cadence.
The Neovim config is the same shape: its own history, its own cadence, useful without the rest,
and the flake should *consume* it, not contain it.

**Proposal: a separate repo, Borgesian name `asterion`** — *La casa de Asterión*: the house with
"fourteen [infinite] doors", every room reachable from every other, its occupant certain no one
else could live there. An editor of infinite windows, built for one person. (Alternatives
considered: `arena` — *El libro de arena*, the infinite-paged book — good, but "arena" collides
with N-way racing vocabulary in the field; `jardin` — forking paths — taken by every second
project.) ficciones → `asterion` becomes a flake input, and `~/.config/nvim` an out-of-store
symlink into a sibling checkout (the `hyprland.lua` pattern) so edits are live and the
palette-rendered colorscheme is written *into* it by `theme:gen`.

**Start lean, not from the December config.** 68 files / 5,270 lines / ~110 specs across six
categories, on a tokyonight base, last touched 2025-12-10. Reviewed, it is a good *reference*
(statusline, statuscol, folds, hackery mode, the Elixir/neotest wiring are worth lifting) and a
poor *base*: it predates the palette law, snacks' consolidation, Neovim 0.12's built-ins, and
every AI plugin in it has been superseded or forked since. Lift by the file, don't inherit by
the tree. (Andrew: "or start a new one if it's cleaner" — it is.)

## 4 · Sequence

Each piece gets a detailed plan the session it starts. Checks are the gates that say "done".

| # | Piece | Detail doc | Check |
|---|---|---|---|
| **A** ✅ BUILT 2026-09-17 (`~/projects/asterion`, gate green, both palettes on screen) | **asterion bootstrap** — repo, flake input, out-of-store symlink, lean core (lazy.nvim, per §5), palette colorscheme from `render.nix`, Elixir/TS LSP, tests, git, terminal. Lift statusline/statuscol/folds from December. | `asterion/docs/plans/2026-09-17-bootstrap.md` | `mise run theme:gen` writes the colorscheme; `theme:contrast` covers the editor pairs; `nvim --headless "+checkhealth"` clean; screenshot on both palettes |
| **B** ◐ FIRST SLICE 2026-09-17 — server: `/api/*` operator door (`d5ba149`); asterion: sidebar · thread buffer · composer · coworker host (`server:claude -- <id>` in a snacks terminal) · COMMITS → `CodeDiff`. Later the same day: awaiting/idle transitions announced in the editor; `t` ATTACHES to the coworker's live tmux window (console-workspace-<ws> / w<ws> / lead-or-t<id>) and hosts one only when none exists. Left: live post→reply with a real coworker (not exercised — a post to a real thread spawns one). | **tlon.nvim inside asterion** — HTTP client to the server; sidebar (workspaces › threads › coworkers with attention); thread buffer + composer (post as operator, wake lead); coworker terminal; COMMITS → diff view. | `asterion/lua/tlon/*` | post from Neovim → coworker replies (live); a coworker's commit opens in diff mode from the thread |
| **C** ✅ BUILT 2026-09-17 (asterion `b389af7`: review.nvim `on_export` → POST to the thread; `<leader>gR` picks the thread) — live wake-on-post not exercised, same reason as B | **Review in Neovim** — inline comments on a diff hunk become thread messages the coworker wakes on; the workline review stage (`review.md`) authored here. | with B | a comment on a hunk appears in `server:dossier` RECENT and wakes the lead |
| **D** ✅ BUILT 2026-09-17 (`2082c06` fence · `92d9c68` deps symlink · `817e0b9` oracle · `0c62663` seancing · `02dd7eb` toast + verbs) | **Field adopts, cheap tier** (survey §4): branch fencing hook · needs-you → shell notification · seancing line in the brief · Oracle tool · symlinked deps into worktrees. | survey §4 #1, #2, #9, #6, #13 | each has a test or a live screenshot |
| **E** ✅ BUILT 2026-09-17 (launcher `>` verbs in `02dd7eb`; `docs/manual` generated + hand pages, `manual:gen`/`manual:check`) | **Omarchy tier**: launcher verb mode over `mise tasks --json`; the operator **manual** (generated from hyprland.lua / mise / palette, rendered in the shell Cheatsheet and in Neovim). | steals §2 O3, O5 | manual has zero hand-maintained duplicates of generated facts |
| **F** ✅ BUILT 2026-09-17 (`0e4358a` playbooks · `31b14a5` #N citations · `697b13e` Stop-hook gate · `f499a9d` routing knob) | **Field adopts, medium tier**: playbooks as rows + `promote_playbook`; `@thread`/`@sha` references; coworker-side stop-hook gates; capability-fit routing knob. | survey §4 #3, #4, #5, #7 | server tests + an eval scenario each |
| **G** ◯ not started — piece B's detailed plan written from tonight's survey: `2026-09-17-one-brain-piece-b-sessions-plan.md` | **One-brain B–E** as already sequenced: sessions → server · Postgres · web UI · Oban (cron verb, budget pre-flight, bucket footer live here). | `2026-09-08-tlon-one-brain-umbrella.md` | unchanged |
| **H** ◯ not started — needs real threads to eval against | **Experiments** (evals, not builds): query-driven brief vs fixed budget; forget-at-recall vs mem0's four verdicts; CHECKS up the evidence hierarchy. | survey §4 #10, #12 | a written result in `docs/research/` |

Order rationale: A–C put the daily surface where he wants it and prove the API boundary the
umbrella said the web UI would prove — earlier and cheaper. D is a day of small wins that also
serve A–C (notifications, fencing). E is the Omarchy half of the north star. F needs the server
API to have settled under B. G continues as planned; nothing here blocks it, and B (sessions to
server) makes tlon.nvim's terminal attach cleaner when it lands. H runs whenever there is an
idle evening.

## 5 · Neovim ecosystem — findings and the decisions they settle

Survey run 2026-09-17 (Sonnet, web). Decisions in bold; every claim has its source.

**Core (0.12, stable 0.12.5).** `vim.pack` is built in but has no event/ft/cmd lazy-loading — measured 180–250 ms vs lazy.nvim's 55–70 ms on 30+ plugins ([vim.pack vs lazy](https://samuellawrentz.com/blog/neovim-vim-pack-vs-lazy-nvim/), [echasnovski guide](https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack)). **Keep lazy.nvim**; `lazy-lock.json` committed is the reproducibility story. LSP via **`vim.lsp.config`/`vim.lsp.enable`** (nvim-lspconfig kept only for filetype defaults, ≥0.11.3) ([native LSP in 0.12](https://dotfiles.substack.com/p/native-lsp-in-neovim-012)). Built-in tree-sitter parsers for common languages; **nvim-treesitter `master` is frozen and breaks on 0.12 — `main` branch, and the `tree-sitter` CLI becomes a flake dependency** ([migration](https://samuellawrentz.com/blog/nvim-treesitter-archived-neovim-0-12-migration/)). `vim._extui` (new cmdline/messages) is experimental — opt in, don't depend ([PR #27855](https://github.com/neovim/neovim/pull/27855)). **`vim.net.request()`** is a built-in HTTP client — tlon.nvim talks to the server from Lua with no curl shell-out. No living Elixir msgpack-RPC client exists (`dm1try/nvim` dead since 2017) — **Neovim is the client, the server never drives the editor.**

**UI for custom screens.** **`snacks.win` + `snacks.layout`** for each screen (roster, thread view, composer via `snacks.input`), **`edgy.nvim`** (v1.10.2, 2026-07) to dock them as persistent panels ([snacks.layout](https://github.com/folke/snacks.nvim/blob/main/docs/layout.md), [edgy](https://github.com/folke/edgy.nvim)). nui.nvim is the older, more granular option; not needed.

**AI/agents.** **`claudecode.nvim`** (coder, ~3.1k★, beta) implements Claude Code's own IDE protocol — a WebSocket MCP server in Neovim, lock file in `~/.claude/ide/`, native diff accept/reject, selection sync, a terminal for the CLI ([repo](https://github.com/coder/claudecode.nvim), [PROTOCOL.md](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md)). **`agentic.nvim`** is the ACP client (Claude Code, Gemini, Codex, OpenCode, **pi**, …; mid-session provider switch) ([repo](https://github.com/carlos-algms/agentic.nvim)). **`sidekick.nvim`** (folke) = Copilot NES with rich diffs + a terminal for any CLI agent, tmux-persistent ([repo](https://github.com/folke/sidekick.nvim)). Decision: **claudecode for Claude Code hosting, agentic for the ACP pane (pi speaks ACP), sidekick for NES; codecompanion as the one quick-chat plugin; avante and opencode.nvim dropped** — Tlön's own thread UI is the chat sidebar.

**Diff & review.** **`codediff.nvim`** (esmuellert, 1.6k★) ports VSCode's actual diff algorithm, with explorer/history/conflicts/staging ([repo](https://github.com/esmuellert/codediff.nvim)). **`review.nvim`** (v1.10.1 released 2026-09-17) sits on it: comments on any line/range/file, per-branch persistence, `]n`/`[n`, and on quit exports every comment as structured AI-ready markdown ([repo](https://github.com/georgeguimaraes/review.nvim)). **Decision: codediff + review, with review's export step redirected to POST into the Tlön thread — piece C is nearly out of the box.** diffview.nvim demoted to fallback. gitsigns, neogit, octo all current.

**Terminals.** Practice is "tmux stays the multiplexer; Neovim embeds and toggles" — matches the server owning coworker windows. **`snacks.terminal` running `tmux attach -t <window>` per coworker, docked by edgy; `flatten.nvim`** so a coworker pane's file-open lands in the parent Neovim ([snacks.terminal](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md), [flatten](https://github.com/willothy/flatten.nvim)). toggleterm optional.

**Project / notes.** **`neovim-project`** — per-git-branch sessions with auto-switch, which maps onto per-thread worktrees; supersedes persistence.nvim ([repo](https://github.com/coffebar/neovim-project)). **`obsidian.nvim`** (obsidian-nvim fork) over neorg/orgmode — Tlön is markdown-native. **`render-markdown.nvim`** for the thread buffer (always rendered, cursor line reveals raw) ([ecosystem doc](https://github.com/MeanderingProgrammer/render-markdown.nvim/blob/main/doc/markdown-ecosystem.md)). Kanban: nothing mature (super-kanban is alpha) — **the board is a `snacks.win` screen over Tlön's ticket rows.** `snacks.dashboard` replaces alpha.

**Folke's stack, Sept 2026.** snacks (umbrella), sidekick (new), edgy, trouble, which-key, flash, lazy all current; noice still "highly experimental" — **drop noice**, core `_extui` is closing the gap; persistence superseded here; tokyonight irrelevant (own palette).

**Theming.** **`base16-nvim`** (RRethy) consumes a full 16-colour Lua table — `render.nix` emits it, no lush/colorbuddy DSL ([repo](https://github.com/RRethy/base16-nvim)). The palette-role law applies: the table is bound in the palette export, the editor names roles.

**Nix.** nixvim/nvf: every tweak is a rebuild, lazy-loading experimental, slower startup ([comparison](https://devctrl.blog/posts/which-one-should-i-use-programs-neovim-nix-cats-nvim-nixvim-or-nvf/)). **Decision: plain Lua config as an out-of-store symlink (the `hyprland.lua` pattern), lazy.nvim owning plugins with a committed lock, Nix owning only Neovim's system deps (ripgrep, fd, lazygit, tree-sitter CLI) and the rendered palette file** — the nixCats philosophy without the dependency.

**Elixir.** **Expert** (0.1.0, 2026-03; unified ElixirLS/Lexical/Next LS) via `vim.lsp.config`; `elixir-tools.nvim` for `:Mix`/projectionist; `neotest-elixir` presumed fine, activity unverified. Re-verify the stdin-Unicode fix (`cb87cb6`) is in the pinned version.

**Risks carried into piece A:** treesitter `main` + CLI dep · claudecode/agentic/codediff/review are young single-maintainer projects — pin via lock, expect breakage · Expert pre-1.0 · pick one of dropbar/incline · avante out.

## 6 · Index of the docs this supersedes or points at

- `2026-09-17-omarchy-atlas-steals.md` — the Omarchy/Atlas steal-list and the shell gap table (§2–§3 there are the E-piece backlog).
- `2026-09-17-orchestrator-field-survey.md` — three-class field survey; §4 is the D/F/H backlog.
- `2026-09-08-tlon-one-brain-umbrella.md` — piece G, unchanged.
- `2026-09-08-cockpit-ux-principles-design.md` — still governs the console as god-view; the keymap rule is why the composer moves.
- `2026-09-02-astal-shell-design.md` — the shell; E adds the verb menu and manual.
- `2026-08-27-ai-native-sdlc-workline-design.md` — worklines; C authors review there, F gives gates teeth.
- `2026-09-01-tlon-roadmap.md` — historical; WS1/2/4 done, WS3 = G.

Memory: `ficciones-north-star-better-omarchy` (2026-09-17).
