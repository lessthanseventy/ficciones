# The ficciones manual

How to drive this machine, today. Omarchy's manual is the bar (master plan piece E): one page
per thing you would look up, and nothing here that could drift — every list that has a source
is **generated from it** by `mise run manual:gen` and checked by `mise run manual:check`
(a mise gate, not a flake check — the keys page reads the live compositor's config). Hand-written pages are short and say
*why*; the generated ones say *what*.

| Page | What it answers | Source |
|---|---|---|
| [keys.md](keys.md) | every keybinding, by group | generated — the `bind(...)` lines of `modules/desktop/hypr/hyprland.lua` (hyprctl binds -j only knows them as `__lua`) |
| [tasks.md](tasks.md) | every verb (`mise run …`), by group | generated — `mise tasks ls --json` |
| [palette.md](palette.md) | the roles, both palettes, the law | generated — `render.nix` |
| [surfaces.md](surfaces.md) | the three surfaces and which one does what | hand |
| [update.md](update.md) | how a change reaches the running machine | hand |
| [tlon.md](tlon.md) | threads, coworkers, briefs, worklines — the operator's view | hand |

Where to look when a page here is not enough: `docs/plans/2026-09-17-ficciones-master-plan.md`
(the plan), `AGENTS.md` (the loop), `modules/*/AGENTS.md` (per module).
