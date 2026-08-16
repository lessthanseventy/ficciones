# Environments over funes — one memory, one bus, many UIs

Written 2026-08-15, in the session that turned the aleph cockpit from a single board into a *family of
environments*. It **extends** the cockpit design (`2026-08-15-aleph-tui-design.md`) rather than replacing
it: that doc settled the frame (one raxol app, sidebars-as-components, a tmux-embedded center) and the
render toolkit; this one settles what the frame is *for* — a shell that hosts many bounded environments
over the one funes spine. The funes spec (`../../modules/funes/docs/spec.md`) still wins on every rule it
states. As with the other records here, it also names the turns it **rejected**, so they do not recur.

The headline: **ficciones is one data model and one communication layer (funes) with many UIs over it.**
Each UI is an *environment* — a bounded domain with its own data, its own coworkers, and its own surface
— named for the Borges story it behaves like. The cockpit (`aleph`) is the shell that hosts them.

---

## 1 · The shape — one spine, one shell, many environments

| Layer | Piece | Its one job |
|---|---|---|
| **The spine** | **funes** | the shared data core (threads, messages, agents, sessions, events), the one comms layer (Channel + Bus), the one Repo + §4 single-writer discipline. Sovereign; depends on nothing above it. |
| **The shell** | **aleph** | the cockpit: the workspace picker, the panel/view/board render toolkit, the input/resize loop. Hosts environments as workspaces; owns no domain data of its own. |
| **The environments** | **congress · senderos · tlön · zahir · compass** | each a bounded domain: its own Ecto schemas + migrations (against funes' one Repo), its own coworkers/skills, its own UI surface. |

**One database, one writer.** funes' spine and every environment's tables live in one SQLite file behind
funes' single Repo, so a cross-environment reference (senderos' `ticket` → a funes `thread`) is an
ordinary foreign key and the §4 single-writer invariant — funes' whole correctness model — still holds.
Postgres stays a deferred Ecto-adapter swap for if/when concurrent writers, a shared server, or scale
actually demand it; sovereignty (a local file, readable with the node dead) is why SQLite stays for now,
and the Ecto boundary keeps the swap contained.

---

## 2 · What an environment is — the anatomy, and when it becomes a module

An environment is **not** a new app by default. It is, in order of how it grows:

1. **A bounded funes context + its schemas.** Its own tables (senderos: `board`/`ticket`/`column`;
   zahir: `incident`) migrated against `Funes.Repo`, referencing funes' shared entities. It owns its
   domain logic; funes owns the spine it references.
2. **Its own topics on the one Bus.** funes' `Funes.Bus` is the single communication layer. An
   environment publishes its own typed events on the same PubSub (`senderos:board:{id}`, …); the cockpit
   and coworkers subscribe. No second bus.
3. **A surface in the cockpit.** A workspace (design §3: "a view is a composition of panels") — the
   picker slots its surface into the center and its situational panels around it.
4. **Its coworkers/skills.** The agents staffed into that environment (funes `Staff`), and the skills
   they carry there.

**Born when it has content; promoted when it earns it.** An environment starts as a workspace +
context *inside* the existing modules, never as an empty `modules/<name>` skeleton (root `AGENTS.md`: the
tree must not lie about what is built). It is **promoted to its own `modules/<name>` mix project only
when it needs its own runtime** — its own OTP processes, release cadence, or agent fleet. At that point
the cockpit stops rendering it in-process and **embeds it through the tmux seam** (design §2/§4): the
environment runs as its own program in a tmux pane, and the cockpit renders a view of it. Contained app
*and* unified shell, with no premature boundary.

---

## 3 · The environments and their names

Module names are Borges (like `funes`, `aleph`); the daily UI labels stay corporate-deadpan (design §1
register). Each environment is named for the story it behaves like — the full glosses live in the root
`README.md` under **The environments**.

| Environment | Module | Story it behaves like | UI label |
|---|---|---|---|
| Chat / coordination | **congress** | *The Congress* — the always-in-session assembly of all participants | CHANNEL |
| Tickets / boards | **senderos** | *The Garden of Forking Paths* — every ticket a branching path | BOARD |
| Workbench / meta / dogfood | **tlön** | *Tlön, Uqbar…* — the invented world that becomes the real one | WORKBENCH |
| Support / incidents | **zahir** | *The Zahir* — the thing that seizes all attention until it clears | SUPPORT |
| Review / investigation | **compass** | *Death and the Compass* — following evidence to its source | REVIEW |

**None are built yet.** They are the vocabulary and the plan; the shell that will host them exists (§5).
`senderos` in particular is a real subsystem, not a feature — a local issue tracker with boards,
swimlanes, folders, and **cross-session tickets** any coworker or the human can file, including against
other boards. It earns its own design pass (funes gains a `board`/`ticket`/`column` model) before it is
built; the cockpit's current **Tickets** workspace is a basic view over funes' existing thread/issue
rows, honestly labelled as the placeholder it is.

---

## 4 · The cockpit shell — what exists now

The shell and its toolkit are built and green (headless render tests; on-screen paint eye-tested):

- **The render toolkit.** `Aleph.Panel` (a panel renders styled rows — `{text, style}` runs — over a
  funes read), `Aleph.Style` (one semantic palette → truecolor), `Aleph.View` (composition → placed
  panels + rules + status bar), `Aleph.Board` (placements → cells → termbox paint). Pure and testable;
  the same panel can later paint in a LiveView (design §7).
- **The workspace layer.** `Aleph.Workspace` (a workspace = a center surface + its situational panels;
  `Aleph.Panel.Workspaces` is the top-left picker). Three starter workspaces — **Terminal** (a live tmux
  view via `Aleph.Tmux` capture/send-keys), **Chat** (funes messages), **Tickets** (funes threads) —
  proving the "pick what's in the middle" model.
- **The live loop.** `Aleph.Cockpit` — one GenServer that *is* the dispatcher: termbox2 paints,
  `Raxol.Terminal.Driver` feeds it keys/resize, `Funes.Bus` events arrive as messages; every input,
  event, and tick reloads the funes reads and repaints. Holds the only shared state — the active
  workspace and the focused thread (design §8). Boots funes for real (Repo + Bus) over the shared DB.

**The center is tmux, not `ghostty_ex`.** The design's fallback became the plan: `raxol_terminal` renders
the board and a tmux pane is viewed via `capture-pane` + driven via `send-keys`. No Zig NIF; tmux stays
the multiplexer (design §2/§5). The full interactive PTY embed (type-into-the-pane latency) remains a
later spike; the capture/send path is the low-risk version that works today.

---

## 5 · Build order

1. **The cockpit shell + reactive board** (done): workspaces, panels, the live loop, over funes.
2. **`senderos` design pass** — the local Jira: funes' `board`/`ticket`/`column` model, cross-session
   tickets, swimlanes/folders, filing across boards. Its own design doc, then built.
3. **The other environments**, each born when it has content: `congress` (chat, largely the current Chat
   workspace grown up), `zahir` (support/incidents), `compass` (review), `tlön` (the dogfood meta-env).
4. **Promotion to modules** as any environment earns its own runtime — via the tmux embed seam.
5. Earned by evidence, as before: the `raxol_liveview` web surface, configurable workspaces, the `Sense`
   collectors and the gauges they light up (aleph design §9).

---

## 6 · Rejected, so it does not recur

- **An Elixir umbrella.** Tightens shared config/deps and undercuts the one thing funes is built for —
  each unit sovereign, travelling independently. The `modules/<name>` + path-dep shape already gives
  "many apps over one funes" without the coupling (aleph design §6 first rejected umbrella; this holds
  it for the whole family).
- **Many independent apps with no shell.** Maximally sovereign but the human juggles programs and every
  UI duplicates chrome. The single pane of glass is worth a shell; the shell embeds sovereign apps
  through tmux rather than replacing them.
- **Pre-building empty environment modules.** Five `modules/*` skeletons to imply a structure that does
  not exist yet. The tree must not lie; an environment is born when it has content.
- **A second database or a Repo per environment.** Breaks cross-environment foreign keys and funes' §4
  single-writer invariant. One file, one Repo, one writer; environments own their *schemas*, not their
  own databases.
- **funes owning every environment's data.** The opposite failure — funes bloats and loses sovereignty
  as each domain leaks into the spine. funes owns the shared spine; environments own their own tables.
