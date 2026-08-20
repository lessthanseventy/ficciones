# Tlön — long-term vision: from dogfood workshop to personalization layer

Date: 2026-08-20
Status: north-star / living doc. Not a slice plan — no work items here. Captures the intended end
state of the Tlön space and the prioritization discipline it implies, so near-term builds can be
checked against it. Born from a 2026-08-20 conversation (operator + `tertius-machine`), cross-read
against `chaitanyagiri/munder-difflin` and the broader multi-agent-harness crop.

## The vision

**Today** Tlön is one specific thing: an isolated dogfood environment with particular opinions about
who is launched (the cast: `tertius`/`hronir`/`uqbar`), what they're doing (building ficciones), and
how they're wired (profiles, permissions, scoping, prompts). It is simultaneously two concepts that
are only indistinguishable because there is exactly one project in the room:

1. **A specific project workspace** — the one building this stack.
2. **A configuration surface** — where coworkers, profiles, prebaked prompts, and workflows get
   defined.

The end state separates them: **(1) demotes to "just another project in the Orbis space,"** since
Orbis is the intended home for project-scoped things, and **(2) remains as the meta-layer** — the
place where you configure all those little bits. Dogfooding does not stop; it stops being the *only*
project. The stack that ate its own tail keeps eating its own tail, as one tenant among many. That is
the honest operating model — not a clean build→release→use cutover, but a gradient where the fraction
of energy on meta-work drops from ~all to ~some, never zero.

This is a change of *what the substrate is pointed at*, not a change of substrate. funes is a
memory + thread + agent system; aleph is a cockpit over it; the boundary law keeps funes sovereign.
That *is* a personalization layer — it just currently points at its own construction. No big
architectural refactor is hiding in this vision; the architecture is already the right shape. What
changes is emphasis, data modeling, and where new code goes.

## What the comparison teaches (munder-difflin et al.)

`munder-difflin` is the sharpest mirror: an Electron/React/Pixi desktop app that wraps the *same*
terminal-agent CLIs we wrap (claude, codex, pi, grok, kimi, …) into a "hive" — per-agent memory +
atomic-file mailboxes + a shared blackboard + an append-only event log + single-committer git —
coordinated by a GOD orchestrator ("Michael") and visualized as avatars on a 2D office floor. It is a
wide feature surface on a thinner substrate. We are a narrower surface on a deeper one. The depth is
the point: it is what makes the wide surface fall out later without re-building the substrate.

**What they work hard for that we get for free** (because the substrate already is it):

| They built | We already have, because |
|---|---|
| Electron shell + xterm.js renderer + node-pty | `ghostty` + real tmux + the aleph TTY cockpit — real terminals, not emulated ones |
| The "hive" (mailboxes, blackboard, event log, single-committer git) | `funes` — threads, messages, facts, the append-only channel. Mailboxes = threads; blackboard = the thread; event log = the message log |
| A GOD orchestrator that routes/adjudicates/escalates | `tertius-machine` (the root meta agent) + `Aleph.Mention` (the cockpit Bus router). Designed, partially staffed |
| Per-agent long-term memory + semantic recall index | `funes` per-thread dossier + the recall layer (post-pivot, see below) |
| BYOK secret broker | the flake already owns `models.json`, ollama + anthropic keys, `agenix` machine secrets |
| Skills catalog (227 skills, install/uninstall) | `manos` + `pi` extensions, declaratively seeded by the flake |
| Circuit breaker (steer/constrain/stop) | `pi-permission-system` + the catastrophic-bash deny-floor (partial — the loop/storm case is open) |
| Cost ledger / real cost from transcripts | `record_check` + cap-aware routing (`ollama:usage`) — measured, not yet a durable ledger |
| Shareable "hires" / agent gallery | coworker *profiles as data* — once the config model lands (see fork below), a profile is a shareable artifact |
| Slack / webhook ingress | the `funes` MCP channel is the ingress; a bridge is a thin client over it |

**What we have that is genuinely novel** — the one to protect and lead with:

- **Forget-at-recall, not at storage.** Their memory "condenses so it doesn't grow forever" — lossy
  compaction applied to the store, so the audit trail degrades as a side effect of keeping context
  sane. Ours (the 2026-08-19 pivot) keeps storage append-only and total (auditable, no loss) and puts
  forgetting at the *recall* layer: a token-budgeted working set returned per turn. The man who never
  forgets goes insane; the office that reloads its whole past every turn goes bankrupt. The cure is
  forgetting — but at recall, so the books stay complete. This is a real difference in memory
  semantics, not a UI difference, and it is the load-bearing novelty.
- **Sovereign boundary.** funes never reaches up into machine config; the `:boundary` compiler
  enforces it. The unit that travels is `modules/funes/`, sovereign on each machine. Their hive is
  welded to their Electron app.
- **One dev loop for human and agent.** The same `mise` tasks drive both; "it works" means the shared
  task passed, not two private ones. They have a separate harness-vs-agent surface.
- **Nix-owned configuration.** Declarative source of truth, reproducible, version-controlled. They
  persist config in SQLite + JSON.

**What they got right that we have not prioritized yet** — worth stealing deliberately, not by
drift:

- **An approvals/escalation queue.** "Escalate only critical items (spend, destructive ops, scope
  changes) into a queue you act on." This is the `herdr`-style attention layer Andrew already wants
  (native notifications, "agent is waiting on you"). We have the permission gate but not the *queue*.
- **A circuit breaker for looping/storming agents** (steer → constrain → stop). Our deny-floor covers
  catastrophic bash; it does not cover the agent that loops forever inside the rules.
- **Durable cost ledger from real transcripts.** We measure checks; we do not yet aggregate cost per
  agent/thread over time into a ledger you can audit.
- **A browsable skills/extensions catalog from the cockpit.** `manos`/`pi` extensions are wired but
  not surfaced as a catalog you install/uninstall from inside aleph.
- **Remote ingress** (Slack/webhook → spawn ephemeral worker → reply in-thread → tear down). A webui
  or chat bridge over the funes channel.

## What "falls out for free" — and the half that doesn't

The claim to scrutinize: a **webui falls out for free.** Half-true, and the half matters.

- **Free: the data and coordination plane.** funes is an HTTP/MCP channel; aleph is one client over
  it. A webui is a *second client over the same channel* — threads, messages, facts, dossiers,
  mentions all reach it without a new backend. munder-difflin had to build the entire Electron +
  Pixi + xterm shell *to get a UI at all*; we already have the channel a UI would talk to. That is
  the real saving.
- **Not free: the rendering and interaction layer.** aleph is TTY/termbox; a webui is a whole new
  renderer (React/whatever) + terminal emulation + the compose/mention/jump interactions, rebuilt
  for the browser. The substrate reuse is total; the surface rebuild is real.

So the honest version: **everything behind the channel is free; the new client surface is work.** The
depth of the substrate is what makes the *first* webui a client project rather than a ground-up
rebuild — which is the whole argument for keeping the substrate deep and the surface thin.

## The one architectural fork to decide deliberately

Where is the source of truth for the config objects — coworkers, profiles, prompts, workflows? Today
they are declared in the flake and applied by `home:switch` (declarative, version-controlled, heavy
to change). If Tlön becomes the *editable* configuration surface, three paths:

1. **Flake stays truth; Tlön is a read/edit view that writes nix and triggers switch.** Faithful to
   current law, but editing nix from a cockpit is awkward and the switch is heavy.
2. **Truth moves into funes** (runtime-editable, stateful; flake only bootstraps). Fluid, but
   stateful config leaves git — in tension with "nix owns packaging and the system."
3. **Hybrid: flake seeds the schema + immutable defaults; funes holds user-authored additions and
   overrides.** Likely where this lands. Needs a clear rule for who wins on conflict and what is
   seedable vs runtime-only.

This gets locked in *by accident* during the dogfood-define-the-shape phase, because every facility
built (permissions, scoping, coworkers) will implicitly assume one of the three. Decide deliberately,
now — it is cheap now and expensive after a year of personal state has accumulated against the
wrong seam.

## The release bar

Capability-shaped bars ("recall works, chat works, gates green") are too soft. The sharper bar this
vision implies:

> **The dogfood-Tlön is fully expressible as configuration, with zero special-casing in aleph/funes
> for "this is THE tlon."**

Concrete test: can a second project that looks just like Tlön (coworkers, scope, prompts, wiring)
be spawned pointed at a different repo, from configuration alone, touching no aleph/funes code? If
yes, the shape is defined and the dogfood is ready to demote to a tenant. If no, there is still
special-casing masquerading as architecture. Some machinery is already moving this way (per-coworker
tmux sockets from `Aleph.Profiles`, the settings panel); the test is whether it is *finished*.

## Prioritization discipline (the one behavioral change to adopt now)

Every piece of currently-special Tlön machinery is debt to generalize before stacking more
Tlön-specific features on top of it. The discipline: when reaching for a new feature, ask *"is this
building onto the special case, or generalizing it?"* Build features as **project-scoped config**,
not as Tlön code — or the generalization gets harder every commit. Concretely:

- Coworker / profile / prompt / workflow become **first-class data with a schema**, not ad-hoc
  `FUNES_*`/`PI_*` env threaded through `tmux new-session -e` and flake seeds. The launch/wiring
  logic is driven by that model, not by hardcoded `tlon` session names and special tabs.
- The scope primitive (`scope: machine` vs `scope: project`) is already first-class; keep
  instantiating projects from it rather than special-casing Tlön.
- New cockpit features land as things any project workspace gets, not things only the Tlön space
  gets.

This does not slow the build — it changes where new code goes. It compounds.

## What does NOT change

The boundary law, the sovereign funes module, the one-mise-loop parity, nix-owned packaging, the
commit-byline rule, the comment standard. The vision is a redirect of the substrate's aim and a
data-modeling discipline, not a rewrite. The architecture is already the personalization layer; the
work is making the dogfood ordinary.