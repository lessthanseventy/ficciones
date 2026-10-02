// The office: a rail on the right (the deck's agents cell toggles it, `astal-shell toggle office`)
// with one workspace's Tlön roster as a pixel-art office (lib/office.ts), then the action card
// (hand a ticket to a coworker, file a ticket, hire), the inbox (threads waiting on you) and the
// picked thread: a prompt's options as buttons, a reply line, its brief. ‹ › walks the workspaces.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Cairo from "cairo"
import GLib from "gi://GLib?version=2.0"
import Pango from "gi://Pango?version=1.0"
import Vte from "gi://Vte?version=3.91"
import { execAsync } from "ags/process"
import { For, createComputed, createState, type Accessor } from "ags"
import { interval, type Timer } from "ags/time"
import { agents, dossier, threadView, post, ticketRoute, closeThread, fileTicket, startTicket, hire, coworkerSet, workspaceNew, aside, fire, ticketSet, ticketDelete, workspaceDelete, handOff, setOpener, type Agents, type Dossier, type Note, type Thread, type ThreadView } from "../lib/agents"
import { OfficeSim, S, W, boardColumns, type BoardItem, type Hit } from "../lib/office"
import { theme } from "../lib/theme"
import { ROLE } from "../lib/palette"
import { Panel } from "../lib/tui"
import { Brief } from "../panes/Agents"
import { armClickaway, closeAny, disarmClickaway } from "./Clickaway"

const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)

// which workspace's office is showing; null = the one that needs you most
const [chosen, setChosen] = createState<number | null>(null)
function busiest(a: Agents): number | null {
  const by = (pred: (ws: number) => boolean) => a.workspaces.find((w) => pred(w.id))?.id
  return by((ws) => a.threads.some((t) => t.workspace_id === ws && needsYou(t))) ?? by((ws) => a.roster.some((r) => r.workspace_id === ws))
    ?? by((ws) => a.bench.some((c) => c.workspace_id === ws)) ?? a.workspaces[0]?.id ?? null
}
const wsId = createComputed(() => chosen() ?? busiest(agents()))
/** the snapshot narrowed to one workspace — what the office draws and acts on */
const view = createComputed((): Agents => {
  const a = agents(), ws = wsId()
  const threads = a.threads.filter((t) => t.workspace_id === ws)
  const bench = a.bench.filter((c) => c.workspace_id === ws)
  const sessions = a.roster.filter((r) => r.workspace_id === ws)
  // a desk for every staffed open thread, not only the ones with a session: a Claude Code worker
  // registers none until it calls register. Without one, a thread's own running window means
  // working — but not the lobby's, whose lead runs there all day
  const unregistered = threads
    .filter((t) => t.lead && !sessions.some((r) => r.thread_id === t.id))
    .map((t) => {
      const c = bench.find((b) => b.name === t.lead)
      return { agent: t.lead!, thread_id: t.id, title: t.title, warm: !!t.live && !t.standing, archetype: c?.archetype ?? null, lead: c?.lead ?? false, workspace_id: ws }
    })
  return {
    ...a, threads, roster: [...sessions, ...unregistered], bench,
    tickets: a.tickets.filter((t) => t.workspace_id === ws), projects: a.projects.filter((p) => p.workspace_id === ws),
    notes: a.notes.filter((n) => n.workspace_id === ws || n.workspace_id === null), visits: a.visits.filter((v) => v.workspace_id === ws),
    awaiting: threads.filter(needsYou).length,
  }
})
const wsName = createComputed(() => agents().workspaces.find((w) => w.id === wsId())?.name ?? "—")
const elsewhere = createComputed(() => { const a = agents(), ws = wsId(); return a.threads.filter((t) => t.workspace_id !== ws && needsYou(t)).length })
function stepWs(d: 1 | -1) {
  const list = agents.peek().workspaces
  if (!list.length) return
  const i = list.findIndex((w) => w.id === wsId.peek())
  setChosen(list[(i + d + list.length) % list.length].id)
  setMode({ kind: "none" })
}
// each workspace keeps its own room, so switching back finds everyone where they were
const sims = new Map<number, OfficeSim>()
const sim = () => { const ws = wsId.peek() ?? 0; let s = sims.get(ws); if (!s) sims.set(ws, (s = new OfficeSim())); return s }

const [picked, setPicked] = createState<number | null>(null)
const [brief, setBrief] = createState<Dossier | null>(null)
const [frame, setFrame] = createState(0)
// wide: the picked thread opens beside the office — its conversation and its worker's pane
const [wide, setWide] = createState(false)
const [tview, setTview] = createState<ThreadView | null>(null)
let viewing = 0
async function loadThreadView() {
  const id = picked.peek(), my = ++viewing
  const v = id === null || !wide.peek() ? null : await threadView(id)
  if (my === viewing) setTview(v)
}
let loading = 0
async function loadBrief() {
  const id = picked.peek()
  const my = ++loading
  const d = id === null ? null : await dossier(id)
  if (my === loading) setBrief(d)
}
picked.subscribe(loadBrief)
picked.subscribe(() => { setTview(null); loadThreadView() })
wide.subscribe(loadThreadView)

type Mode =
  | { kind: "none" }
  | { kind: "ticket"; id: number }
  | { kind: "confirm"; id: number; agentId: number; name: string }
  | { kind: "new-ticket" }
  | { kind: "hire" }
  | { kind: "coworker"; agentId: number }
  | { kind: "new-workspace" }
  | { kind: "workspace" }
  | { kind: "handoff"; tid: number }
  | { kind: "confirm-handoff"; tid: number; name: string }
  | { kind: "column"; col: number }
  | { kind: "notes" }
  | { kind: "boss" }
const [mode, setMode] = createState<Mode>({ kind: "none" })
// asides, by agent id: survive closing the card, so reopening someone shows what they last said
const [talks, setTalks] = createState<Record<number, { name: string; q: string; a: string | null }>>({})
const armed = mode((m) => (m.kind === "ticket" || m.kind === "confirm" ? m.id : null))
const armedTitle = createComputed(() => { const id = armed(); return agents().tickets.find((t) => t.id === id)?.title ?? "" })

const inbox = view((a) => a.threads.filter(needsYou))
const pickedThread = createComputed(() => { const id = picked(); return agents().threads.find((t) => t.id === id) ?? null })
// a staffed thread can be closed and so missing from `threads`; its roster row still names it
const pickedTitle = createComputed(() => {
  const id = picked(), a = agents()
  const title = a.threads.find((t) => t.id === id)?.title ?? a.roster.find((r) => r.thread_id === id)?.title ?? ""
  // a panel title cannot ellipsize, and a long one would widen the whole rail
  return id === null ? "" : `#${id}  ${title.length > 40 ? `${title.slice(0, 39)}…` : title}`
})

function act(h: Hit) {
  const m = mode.peek(), x = h.act
  if (x.kind === "boss") setMode(m.kind === "boss" ? { kind: "none" } : { kind: "boss" })
  else if (x.kind === "notes") setMode(m.kind === "notes" ? { kind: "none" } : { kind: "notes" })
  else if (x.kind === "column") setMode(m.kind === "column" && m.col === x.col ? { kind: "none" } : { kind: "column", col: x.col })
  else if (x.kind === "pen") setMode({ kind: "new-ticket" })
  else if (x.kind === "hire") setMode({ kind: "hire" })
  else if (x.kind === "ticket") setMode(m.kind === "ticket" && m.id === x.id ? { kind: "none" } : { kind: "ticket", id: x.id })
  else if (x.kind === "person" && m.kind === "ticket" && x.agentId !== null) setMode({ kind: "confirm", id: m.id, agentId: x.agentId, name: x.name })
  else if (x.kind === "person" && m.kind === "handoff") setMode({ kind: "confirm-handoff", tid: m.tid, name: x.name })
  else if (x.kind === "person") {
    if (x.agentId !== null) setMode({ kind: "coworker", agentId: x.agentId })
    if (x.tid !== null) setPicked(x.tid)
  } else if (x.kind === "thread") setPicked(x.tid)
}

function Scene() {
  let area: Gtk.DrawingArea | null = null
  let hits: Hit[] = []
  const hitAt = (x: number, y: number) => hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)

  const draw = (_: Gtk.DrawingArea, cr: Cairo.Context, w: number) => {
    const m = mode.peek()
    const focus = m.kind === "coworker" ? view.peek().bench.find((c) => c.agent_id === m.agentId)?.name ?? null : null
    const out = sim().draw(cr, w, view.peek(), picked.peek(), armed.peek(), focus)
    hits = out.hits
    if (area && area.heightRequest !== out.height * S) area.heightRequest = out.height * S
  }

  const redraw = () => area?.queue_draw()
  view.subscribe(redraw); frame.subscribe(redraw); picked.subscribe(redraw); theme.subscribe(redraw); mode.subscribe(redraw)
  return (
    <Gtk.DrawingArea
      widthRequest={W * S}
      heightRequest={240 * S}
      hasTooltip
      $={(self) => {
        area = self
        self.set_draw_func(draw)
        const click = new Gtk.GestureClick({ button: 1 })
        // a click on nothing is the way home: whatever was open closes
        click.connect("pressed", (_, _n, x, y) => { const h = hitAt(x, y); if (h) act(h); else { setMode({ kind: "none" }); setPicked(null) } })
        self.add_controller(click)
        const motion = new Gtk.EventControllerMotion()
        motion.connect("motion", (_, x, y) => self.set_cursor_from_name(hitAt(x, y) ? "pointer" : null))
        self.add_controller(motion)
        self.connect("query-tooltip", (_, x, y, _kb, tip) => { const h = hitAt(x, y); if (!h) return false; tip.set_text(h.tip); return true })
      }}
    />
  )
}

/** ‹ workspace › — and how many threads wait on you in the other offices */
function Switcher() {
  return (
    <box spacing={8} cssClasses={["office-switch"]}>
      <button cssClasses={["act"]} onClicked={() => stepWs(-1)} tooltipText="previous workspace"><label label="‹" /></button>
      <button cssClasses={["ws-name"]} hexpand tooltipText="this workspace" onClicked={() => setMode({ kind: "workspace" })}>
        <label cssClasses={["amber"]} label={wsName} ellipsize={3} maxWidthChars={24} />
      </button>
      <label cssClasses={["pink", "sm"]} label={elsewhere((n) => `! ${n} elsewhere`)} visible={elsewhere((n) => n > 0)} />
      <button cssClasses={["act"]} onClicked={() => stepWs(1)} tooltipText="next workspace"><label label="›" /></button>
      <button cssClasses={["act"]} onClicked={() => setMode({ kind: "new-workspace" })} tooltipText="new workspace"><label label="+" /></button>
      <button cssClasses={["act"]} onClicked={() => setWide(!wide.peek())} tooltipText={wide((w) => (w ? "back to the rail" : "wide: the thread beside the office"))}><label label={wide((w) => (w ? "⤡" : "⤢"))} /></button>
    </box>
  )
}

const EFFORTS = ["low", "medium", "high", "xhigh", "max"]
const shortModel = (key: string) => key.replace(/^[^/]*\//, "").replace(/^claude-/, "")
const harnessName = (h: string) => (h === "claude_code" ? "claude code" : h)
const choiceLabel = (key: string) => {
  const m = agents.peek().models.find((x) => x.key === key)
  return m ? `${shortModel(key)} · ${harnessName(m.harness)}` : shortModel(key)
}
const archOf = (name: string | null) => agents.peek().archetypes.find((a) => a.name === name)
/** what an archetype changes beyond its prompt, in a line */
const archFacts = (name: string | null, lead = false) => {
  const a = archOf(name)
  if (!a) return ""
  return [a.name, a.meta && "manager: routes the work, never works a thread", lead && "the lead: works whatever is started without the manager", a.read_only && "read-only (cannot write)", `default ${choiceLabel(a.model)}`].filter(Boolean).join(" · ")
}

type Setter<T> = (v: T) => void
/** model (with the harness it runs under), effort, ask/allow — null on a knob is the archetype's default */
function Knobs({ model, setModel, effort, setEffort, ask, setAsk }: {
  model: Accessor<string | null>; setModel: Setter<string | null>
  effort: Accessor<string | null>; setEffort: Setter<string | null>
  ask: Accessor<string | null>; setAsk: Setter<string | null>
}) {
  const chip = (on: Accessor<boolean>) => on((x) => ["act", ...(x ? ["chip"] : [])])
  const rows = agents((a) => [null, ...a.models.map((m) => m.key)])
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <label cssClasses={["k", "sm"]} label="model" xalign={0} />
      {/* two to a row: the labels carry the harness */}
      {[0, 2, 4, 6].map((from) => (
        <box spacing={6}>
          <For each={rows((r) => r.slice(from, from + 2))}>
            {(key: string | null) => (
              <button cssClasses={chip(model((m) => m === key))} onClicked={() => setModel(key)}>
                <label label={key === null ? "default" : choiceLabel(key)} />
              </button>
            )}
          </For>
        </box>
      ))}
      <label cssClasses={["k", "sm"]} label="effort" xalign={0} />
      <box spacing={6}>
        {[null, ...EFFORTS].map((e) => (
          <button cssClasses={chip(effort((x) => x === e))} onClicked={() => setEffort(e)}><label label={e ?? "default"} /></button>
        ))}
      </box>
      <label cssClasses={["k", "sm"]} label="permissions" xalign={0} />
      <box spacing={6}>
        {([[null, "default"], ["ask", "ask first"], ["allow", "just do it"]] as const).map(([v, l]) => (
          <button cssClasses={chip(ask((x) => x === v))} onClicked={() => setAsk(v)}><label label={l} /></button>
        ))}
      </box>
    </box>
  )
}

/** the card under the scene for whatever the last click started */
function ActionCard() {
  let title: Gtk.Entry, body: Gtk.Entry, name: Gtk.Entry, wsNameEntry: Gtk.Entry, wsRepo: Gtk.Entry
  const [project, setProject] = createState<number | null>(null)
  const [arch, setArch] = createState<string | null>(null)
  const [model, setModel] = createState<string | null>(null)
  const [effort, setEffort] = createState<string | null>(null)
  const [ask, setAsk] = createState<string | null>(null)
  const cancel = () => setMode({ kind: "none" })
  const is = (k: Mode["kind"]) => mode((m) => m.kind === k)
  const coworker = createComputed(() => { const m = mode(); return m.kind === "coworker" ? agents().bench.find((c) => c.agent_id === m.agentId) ?? null : null })
  // a destructive button arms on the first click and acts on the second; a new card disarms it
  const [sure, setSure] = createState<string | null>(null)
  const danger = (key: string, label: string, run: () => Promise<unknown>) => (
    <button cssClasses={["act", "red"]} onClicked={async () => { if (sure.peek() !== key) setSure(key); else { setSure(null); await run() } }}>
      <label label={sure((s) => (s === key ? `really ${label}?` : label))} />
    </button>
  )
  // the knobs open on what is set now: a coworker's policy, or nothing (the archetype's) for a hire
  mode.subscribe(() => {
    const c = coworker.peek()
    setModel(c?.model ? `${c.model.provider}/${c.model.model}` : null)
    setEffort(c?.model?.thinking ?? null)
    setAsk(c?.ask ?? null)
    setSure(null)
    const m = mode.peek()
    if (m.kind === "ticket" && ticketTitle) ticketTitle.text = agents.peek().tickets.find((t) => t.id === m.id)?.title ?? ""
  })
  let ticketTitle: Gtk.Entry | null = null
  // who manages this office (its meta coworker) and who leads it — the ticket card names them
  const managerName = view((a) => a.bench.find((c) => a.archetypes.find((x) => x.name === c.archetype)?.meta)?.name ?? null)
  const leadName = view((a) => a.bench.find((c) => c.lead)?.name ?? null)
  const armedRouted = createComputed(() => { const id = armed(); return !!agents().tickets.find((t) => t.id === id)?.routed })
  const columns = view((a) => boardColumns(a))
  const columnItems = createComputed(() => { const m = mode(); return m.kind === "column" ? columns()[m.col]?.items ?? [] : [] })
  const heir = createComputed(() => { const ws = wsId(); return agents().workspaces.filter((w) => w.id !== ws).sort((p, q) => p.id - q.id)[0] ?? null })
  const wsThreads = view((a) => a.threads.length)
  const base = createComputed(() => archOf(mode().kind === "hire" ? arch() : coworker()?.archetype ?? null)?.model ?? "")
  // an effort on the default model still needs a model named, so it names the archetype's
  const modelKnob = (unset: string) => model.peek() ?? (effort.peek() ? base.peek() : unset)
  const submitWorkspace = async () => {
    const n = wsNameEntry.text.trim()
    if (!n) return
    if (await workspaceNew(n, wsRepo.text.trim())) {
      wsNameEntry.text = ""; wsRepo.text = ""; cancel()
      const w = agents.peek().workspaces.find((x) => x.name === n)
      if (w) setChosen(w.id)
    }
  }
  const [settings, setSettings] = createState(false)
  const [more, setMore] = createState(false)
  // the last thing you said to whoever's card is open, and their answer (null while they think)
  const exchange = createComputed(() => { const c = coworker(); return c ? talks()[c.agent_id] ?? null : null })
  const talkTo = async (q: string) => {
    const c = coworker.peek(), ws = wsId.peek(), room = sim()
    if (!c || ws === null || !q.trim()) return
    setTalks({ ...talks.peek(), [c.agent_id]: { name: c.name, q: q.trim(), a: null } })
    room.say(c.name, null)
    const a = await aside(ws, c.agent_id, q.trim())
    setTalks({ ...talks.peek(), [c.agent_id]: { name: c.name, q: q.trim(), a: a || "(no answer)" } })
    room.say(c.name, a || "...")
  }
  const dismiss = () => {
    const c = coworker.peek()
    if (!c) return
    const rest = { ...talks.peek() }
    delete rest[c.agent_id]
    setTalks(rest)
  }
  const saveCoworker = async () => {
    const c = coworker.peek(), ws = wsId.peek()
    if (!c || ws === null) return
    if (await coworkerSet(ws, c.agent_id, modelKnob("inherit"), effort.peek() ?? "-", ask.peek() ?? "inherit")) cancel()
  }
  const submitTicket = async () => {
    const ws = wsId.peek()
    if (ws === null || !title.text.trim()) return
    if (await fileTicket(ws, project.peek(), title.text.trim(), body.text.trim())) { title.text = ""; body.text = ""; cancel() }
  }
  const submitHire = async () => {
    const ws = wsId.peek(), n = name.text.trim().toLowerCase(), a = arch.peek()
    if (ws === null || !/^[a-z][a-z0-9-]*$/.test(n) || !a) return
    if (await hire(ws, n, a, modelKnob("-"), effort.peek() ?? "-", ask.peek() ?? "-")) { name.text = ""; cancel() }
  }
  const start = async (agentId: number | null) => {
    const m = mode.peek()
    if (m.kind !== "ticket" && m.kind !== "confirm") return
    if (await startTicket(m.id, agentId)) cancel()
  }
  return (
    <Panel title={createComputed(() => {
      const m = mode()
      switch (m.kind) {
        case "none": return ""
        case "new-ticket": return "\u{f0e7e}  NEW TICKET"
        case "hire": return "\u{f0004}  HIRE"
        case "new-workspace": return "\u{f0004}  NEW WORKSPACE"
        case "workspace": return `\u{f0004}  ${wsName()}`
        case "coworker": return `\u{f0004}  ${coworker()?.name ?? ""}`
        case "handoff": case "confirm-handoff": return `\u{f0e7e}  HAND OFF #${m.tid}`
        case "column": { const col = columns()[m.col]; return `\u{f0e7e}  ${col?.name ?? ""} · ${col?.items.length ?? 0}` }
        case "notes": return `\u{f0e7e}  NOTES · ${view().notes.length}`
        case "boss": return "\u{f0004}  YOU"
        default: return `\u{f0e7e}  TICKET #${m.id}`
      }
    })} cssClasses={["card", "card-agents"]} vexpand visible={mode((m) => m.kind !== "none")}>
      <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
      {/* your desk: what waits on you, and the running of the office */}
      <box orientation={Gtk.Orientation.VERTICAL} spacing={8} visible={is("boss")}>
        <label cssClasses={inbox((l) => (l.length ? ["pink"] : ["dim"]))} label={inbox((l) => (l.length ? `${l.length} waiting on you` : "nothing waits on you"))} xalign={0} />
        <box orientation={Gtk.Orientation.VERTICAL}>
          <For each={inbox}>
            {(t: Thread) => (
              <button cssClasses={["row", "thread-row"]} onClicked={() => { setPicked(t.id); cancel() }}>
                <box spacing={8}>
                  <label cssClasses={["dim", "sm"]} label={`#${t.id}`} widthChars={4} xalign={1} />
                  <label label={t.title} hexpand xalign={0} ellipsize={3} maxWidthChars={22} />
                  <label cssClasses={["pink", "sm"]} label={t.prompt?.summary ?? t.lead ?? ""} ellipsize={3} maxWidthChars={16} />
                </box>
              </button>
            )}
          </For>
        </box>
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "hire" })}><label label="hire someone" /></button>
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "new-ticket" })}><label label="new ticket" /></button>
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "notes" })}><label label="notes" /></button>
        </box>
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "workspace" })}><label label="this workspace" /></button>
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "new-workspace" })}><label label="new workspace" /></button>
        </box>
      </box>
      {/* the notes on the board's strip, newest first: who left them, when, what they say */}
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("notes")}>
        <label cssClasses={["dim"]} label="no notes yet — coworkers leave them with write_note" xalign={0} wrap visible={view((a) => a.notes.length === 0)} />
        <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} propagateNaturalHeight maxContentHeight={320}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
            <For each={view((a) => a.notes)}>
              {(n: Note) => (
                <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
                  <box spacing={8}>
                    <label cssClasses={["cyan", "sm"]} label={n.author} xalign={0} />
                    <label cssClasses={["dim", "sm"]} label={new Date(n.at).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })} xalign={0} />
                  </box>
                  <label label={n.body} xalign={0} wrap maxWidthChars={44} lines={6} ellipsize={3} selectable tooltipText={n.body} />
                </box>
              )}
            </For>
          </box>
        </scrolledwindow>
      </box>
      {/* a whiteboard column as a list: the titles the stickies have no room for */}
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={is("column")}>
        <label cssClasses={["dim"]} label="nothing here" xalign={0} visible={columnItems((l) => l.length === 0)} />
        <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} propagateNaturalHeight maxContentHeight={300}>
          <box orientation={Gtk.Orientation.VERTICAL}>
            <For each={columnItems}>
              {(it: BoardItem) => (
                <button cssClasses={["row", "thread-row"]} onClicked={() => (it.act.kind === "ticket" ? setMode({ kind: "ticket", id: it.act.id }) : it.act.kind === "thread" && setPicked(it.act.tid))}>
                  <box spacing={8}>
                    <label cssClasses={["dim", "sm"]} label={`#${it.act.kind === "ticket" ? it.act.id : it.act.kind === "thread" ? it.act.tid : ""}`} widthChars={4} xalign={1} />
                    <label cssClasses={it.asks ? ["pink"] : []} label={it.title} hexpand xalign={0} ellipsize={3} maxWidthChars={26} tooltipText={it.title} />
                    <label cssClasses={["dim", "sm"]} label={it.act.kind === "ticket" ? (it.high ? "high" : "") : it.who ? `${it.who} · ${it.stage}` : it.stage} />
                  </box>
                </button>
              )}
            </For>
          </box>
        </scrolledwindow>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("workspace")}>
        <label cssClasses={["dim", "sm"]} label={createComputed(() => (heir() ? `deleting it moves its ${wsThreads()} open thread(s) to ${heir()!.name}; its bench goes` : "the only workspace — threads need a home, so it stays"))} xalign={0} wrap maxWidthChars={44} />
        <box spacing={6}>
          <box visible={heir((h) => !!h)}>{danger("workspace", "delete this workspace", async () => {
            const ws = wsId.peek()
            if (ws !== null && (await workspaceDelete(ws))) { setChosen(null); cancel() }
          })}</box>
          <button cssClasses={["act"]} onClicked={cancel}><label label="close" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("handoff")}>
        <label label={mode((m) => (m.kind === "handoff" ? `click the coworker to hand #${m.tid} to` : ""))} xalign={0} />
        <label cssClasses={["dim", "sm"]} label="they pick it up from the thread's brief; whoever has it now stops" xalign={0} wrap maxWidthChars={44} />
        <button cssClasses={["act"]} halign={Gtk.Align.START} onClicked={cancel}><label label="cancel" /></button>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("confirm-handoff")}>
        <label cssClasses={["amber"]} label={mode((m) => (m.kind === "confirm-handoff" ? `hand #${m.tid} to ${m.name}?` : ""))} xalign={0} />
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={async () => { const m = mode.peek(); if (m.kind === "confirm-handoff" && (await handOff(m.tid, m.name))) cancel() }}><label label="hand it over" /></button>
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("coworker")}>
        <entry cssClasses={["deck-entry"]} placeholderText={coworker((c) => `say something to ${c?.name ?? ""}…`)} $={(self) => { talkEntry = self; self.connect("activate", () => { talkTo(self.text); self.text = "" }) }} />
        <box spacing={6} visible={exchange((x) => !!x)}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={3} hexpand>
            <label cssClasses={["dim"]} label={exchange((x) => (x ? `you: ${x.q}` : ""))} xalign={0} wrap maxWidthChars={42} />
            {/* a long answer folds to ten lines, so it cannot push the rest of the rail away */}
            <label cssClasses={exchange((x) => (x?.a === null ? ["dim"] : ["amber"]))} label={exchange((x) => (x ? `${x.name}: ${x.a ?? "thinking…"}` : ""))} xalign={0} wrap maxWidthChars={42} selectable
              lines={more((m) => (m ? -1 : 10))} ellipsize={more((m) => (m ? 0 : 3))} />
            <button cssClasses={["act"]} halign={Gtk.Align.START} visible={exchange((x) => (x?.a?.length ?? 0) > 420)} onClicked={() => setMore(!more.peek())}>
              <label label={more((m) => (m ? "less ▴" : "more ▾"))} />
            </button>
          </box>
          {/* dismiss an answered exchange; one still waiting on its answer stays */}
          <button cssClasses={["act"]} valign={Gtk.Align.START} tooltipText="dismiss" visible={exchange((x) => x?.a != null)} onClicked={dismiss}><label label="×" /></button>
        </box>
        <label cssClasses={["dim", "sm"]} label={coworker((c) => (c ? archFacts(c.archetype, c.lead) : ""))} xalign={0} wrap maxWidthChars={44} />
        <button cssClasses={["act"]} halign={Gtk.Align.START} onClicked={() => setSettings(!settings.peek())}><label label={settings((s) => (s ? "settings ▴" : "settings ▾"))} /></button>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={settings}>
          <Knobs model={model} setModel={setModel} effort={effort} setEffort={setEffort} ask={ask} setAsk={setAsk} />
          <label cssClasses={["dim", "sm"]} label="takes effect from their next session" xalign={0} />
          <box spacing={6}>
            <button cssClasses={["act"]} onClicked={saveCoworker}><label label="save" /></button>
            <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
            {danger("fire", "let go", async () => { const c = coworker.peek(); if (c && (await fire(c.seat_id, c.name))) cancel() })}
          </box>
          <label cssClasses={["dim", "sm"]} visible={sure((s) => s === "fire")} xalign={0} wrap maxWidthChars={44}
            label={coworker((c) => { const n = c ? view.peek().roster.filter((r) => r.agent === c.name).length : 0; return n ? `their ${n} thread(s) stop until you hand them to someone` : "they have no threads" })} />
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("new-workspace")}>
        <entry cssClasses={["deck-entry"]} placeholderText="name" $={(self) => { wsNameEntry = self; self.connect("activate", () => wsRepo.grab_focus()) }} />
        <entry cssClasses={["deck-entry"]} placeholderText="repo path (optional) — where its coworkers work" $={(self) => { wsRepo = self; self.connect("activate", submitWorkspace) }} />
        <label cssClasses={["dim", "sm"]} label="it opens empty: hire at the help-wanted desk; the first builder leads" xalign={0} wrap maxWidthChars={44} />
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={submitWorkspace}><label label="create" /></button>
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("ticket")}>
        {/* the title edits in place: Enter saves it */}
        <entry cssClasses={["deck-entry"]} $={(self) => {
          ticketTitle = self
          self.connect("activate", () => { const m = mode.peek(); if (m.kind === "ticket" && self.text.trim()) ticketSet(m.id, "title", self.text.trim()) })
        }} />
        <label cssClasses={["dim", "sm"]} label={armedRouted((r) => (r ? `with ${managerName.peek() ?? "the manager"} to staff — or click a coworker to hand it over yourself` : "send it to the manager, or click a coworker in the office to hand it over yourself"))} xalign={0} wrap maxWidthChars={44} />
        <box spacing={6}>
          <button cssClasses={["act"]} visible={managerName((n) => !!n)} onClicked={async () => { const m = mode.peek(); if (m.kind === "ticket" && (await ticketRoute(m.id))) cancel() }}>
            <label label={managerName((n) => `send to ${n}`)} />
          </button>
          <button cssClasses={["act"]} onClicked={() => start(null)}><label label={leadName((n) => (n ? `start with ${n} directly` : "start with the lead"))} /></button>
          <button cssClasses={["act"]} onClicked={async () => { const m = mode.peek(); if (m.kind === "ticket" && (await ticketSet(m.id, "status", "done"))) cancel() }}><label label="done" /></button>
          {danger("ticket", "delete", async () => { const m = mode.peek(); if (m.kind === "ticket" && (await ticketDelete(m.id))) cancel() })}
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("confirm")}>
        <label cssClasses={["amber"]} label={mode((m) => (m.kind === "confirm" ? `start #${m.id} with ${m.name}?` : ""))} xalign={0} />
        <label label={armedTitle} xalign={0} wrap maxWidthChars={40} />
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={() => { const m = mode.peek(); if (m.kind === "confirm") start(m.agentId) }}><label label="start" /></button>
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("new-ticket")}>
        <entry cssClasses={["deck-entry"]} placeholderText="title" $={(self) => { title = self; self.connect("activate", () => body.grab_focus()) }} />
        <entry cssClasses={["deck-entry"]} placeholderText="details (optional)" $={(self) => { body = self; self.connect("activate", submitTicket) }} />
        <box spacing={6} visible={view((a) => a.projects.length > 0)}>
          <For each={view((a) => a.projects)}>
            {(p: { id: number; name: string }) => (
              <button cssClasses={project((x) => ["act", ...(x === p.id ? ["chip"] : [])])} onClicked={() => setProject(project.peek() === p.id ? null : p.id)}><label label={p.name} /></button>
            )}
          </For>
        </box>
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={submitTicket}><label label="file" /></button>
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("hire")}>
        <entry cssClasses={["deck-entry"]} placeholderText="name (lowercase, one word)" $={(self) => { name = self; self.connect("activate", submitHire) }} />
        {/* three to a row, so the rail keeps its width */}
        {[0, 3].map((from) => (
          <box spacing={6}>
            <For each={agents((a) => a.archetypes.slice(from, from + 3).map((x) => x.name))}>
              {(k: string) => (
                <button cssClasses={arch((x) => ["act", ...(x === k ? ["chip"] : [])])} onClicked={() => setArch(k)}><label label={k} /></button>
              )}
            </For>
          </box>
        ))}
        <label cssClasses={["dim", "sm"]} label={arch((a) => archFacts(a))} visible={arch((a) => !!a)} xalign={0} wrap maxWidthChars={44} />
        <Knobs model={model} setModel={setModel} effort={effort} setEffort={setEffort} ask={ask} setAsk={setAsk} />
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={submitHire}><label label="hire" /></button>
          <button cssClasses={["act"]} onClicked={cancel}><label label="cancel" /></button>
        </box>
      </box>
      </box>
      </scrolledwindow>
    </Panel>
  )
}

// the wide view's terminal: a client of the workspace's tmux server on a session GROUPED with the
// workers' one — it shares their windows but has its own current window, so it never moves the
// cockpit's view — and it ends itself when this client goes. One client; a thread in another
// workspace respawns it against that workspace's server.
let liveTerm: Vte.Terminal | null = null
let liveWs: number | null = null
let livePid = 0
/** attach to whatever the wide view shows now — the office coming back up re-attaches */
let reattach = () => {}
function endTerminal() {
  if (livePid) execAsync(["kill", String(livePid)]).catch(() => {})
  livePid = 0; liveWs = null
}
function attachTerminal(ws: number, window: string) {
  if (!liveTerm) return
  const sock = `console-workspace-${ws}`
  if (liveWs === ws && livePid) {
    execAsync(["tmux", "-L", sock, "select-window", "-t", `office:=${window}`]).catch(() => {})
    return
  }
  endTerminal()
  liveWs = ws
  liveTerm.reset(true, true)
  liveTerm.spawn_async(Vte.PtyFlags.DEFAULT, null,
    ["tmux", "-L", sock, "new-session", "-A", "-s", "office", "-t", `w${ws}`, ";", "set-option", "destroy-unattached", "on", ";", "select-window", "-t", `office:=${window}`],
    null, GLib.SpawnFlags.SEARCH_PATH, null, -1, null, (_t, pid) => { livePid = pid })
}

/** the wide view's second column: the picked thread's actions, its worker's live terminal, its conversation */
function ThreadPane() {
  const hhmm = (iso: string) => { const d = new Date(iso); return isNaN(d.getTime()) ? "" : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }
  let convo: Gtk.ScrolledWindow | null = null
  // the newest message in view: scroll to the bottom whenever the conversation changes
  tview.subscribe(() => setTimeout(() => { const v = convo?.get_vadjustment(); if (v) v.set_value(v.get_upper()) }, 50))
  // the terminal follows the picked thread's window while the wide view shows; gone, it ends
  const target = createComputed(() => {
    const v = tview(), t = pickedThread(), on = wide()
    return on && v?.window && t?.workspace_id != null ? `${t.workspace_id}:${v.window}` : null
  })
  reattach = () => {
    const k = target.peek()
    if (!k) return endTerminal()
    attachTerminal(Number(k.slice(0, k.indexOf(":"))), k.slice(k.indexOf(":") + 1))
  }
  target.subscribe(() => reattach())
  return (
    <box cssClasses={["sheet", "right", "office-thread"]} orientation={Gtk.Orientation.VERTICAL} spacing={8} widthRequest={720} visible={createComputed(() => wide() && picked() !== null)}>
      <Panel title={tview((v) => `\u{f018d}  ${pickedTitle.peek()}${v?.window ? `  ·  ${v.window} — click in to type` : ""}`)} cssClasses={["card", "card-agents"]} vexpand>
        <ThreadActions />
        <label cssClasses={["dim"]} label="no window is running this thread" xalign={0} visible={tview((v) => !!v && !v.window)} />
        <Vte.Terminal vexpand hexpand visible={tview((v) => !!v?.window)} $={(self) => {
          liveTerm = self
          self.set_font(Pango.FontDescription.from_string("ComicShannsMono Nerd Font Mono 11"))
          const rgba = (hex: string) => { const c = new Gdk.RGBA(); c.parse(hex); return c }
          self.set_colors(rgba(ROLE.prose), rgba(ROLE.ground), null)
          self.connect("child-exited", () => { livePid = 0; liveWs = null })
        }} />
      </Panel>
      <Panel title={"\u{f0e7e}  CONVERSATION"} cssClasses={["card", "card-agents"]}>
        <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} propagateNaturalHeight maxContentHeight={260} $={(self) => { convo = self }}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
            <For each={tview((v) => v?.messages ?? [])}>
              {(m: ThreadView["messages"][number]) => (
                <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
                  <box spacing={8}>
                    <label cssClasses={m.author === "andrew" ? ["amber", "sm"] : ["cyan", "sm"]} label={m.author} xalign={0} />
                    <label cssClasses={["dim", "sm"]} label={hhmm(m.at)} xalign={0} />
                    <label cssClasses={["pink", "sm"]} label="asks" visible={m.kind === "prompt"} />
                  </box>
                  <label label={m.body} xalign={0} wrap maxWidthChars={80} selectable />
                </box>
              )}
            </For>
            <label cssClasses={["dim"]} label="loading…" visible={tview((v) => !v)} xalign={0} />
          </box>
        </scrolledwindow>
      </Panel>
    </box>
  )
}

/** a thread's two verbs beside its terminal: give it to someone else, or close it as done */
function ThreadActions() {
  return (
    <box spacing={6}>
      <button cssClasses={["act"]} onClicked={() => { const id = picked.peek(); if (id !== null) setMode({ kind: "handoff", tid: id }) }}><label label="hand to…" /></button>
      <button cssClasses={["act"]} onClicked={async () => { const id = picked.peek(); if (id !== null && (await closeThread(id))) setPicked(null) }}><label label="close (done)" /></button>
    </box>
  )
}

function Reply() {
  let entry: Gtk.Entry
  const send = async (body: string) => {
    const id = picked.peek()
    if (id === null || !body.trim()) return
    if (await post(id, body.trim())) { entry.text = ""; loadBrief() }
  }
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box spacing={6} visible={pickedThread((t) => !!t?.prompt)}>
        <label cssClasses={["pink"]} label={pickedThread((t) => t?.prompt?.summary ?? "")} xalign={0} hexpand wrap maxWidthChars={36} />
      </box>
      <box spacing={6} visible={pickedThread((t) => (t?.prompt?.options?.length ?? 0) > 0)}>
        <For each={pickedThread((t) => t?.prompt?.options ?? [])}>
          {(o: { key: string; label: string }) => (
            <button cssClasses={["act"]} onClicked={() => send(o.key)} tooltipText={`answer ${o.key}`}><label label={`${o.key} ${o.label}`} /></button>
          )}
        </For>
      </box>
      <entry cssClasses={["deck-entry"]} placeholderText="reply to the thread…" $={(self) => { entry = self; self.connect("activate", () => send(self.text)) }} />
      <box spacing={6} visible={pickedThread((t) => !!t)}>
        <button cssClasses={["act"]} onClicked={() => { const id = picked.peek(); if (id !== null) setMode({ kind: "handoff", tid: id }) }}>
          <label label="hand to…" />
        </button>
        {/* done: the thread closes, its ticket is done, a child reports up; a reply reopens it */}
        <button cssClasses={["act"]} onClicked={async () => { const id = picked.peek(); if (id !== null && (await closeThread(id))) setPicked(null) }}>
          <label label="close (done)" />
        </button>
      </box>
    </box>
  )
}

// the detail box under the room: fixed, so the rail never jumps as cards come and go
const DETAIL_H = 380
let officeWin: Astal.Window | null = null
let ticker: Timer | null = null
let peeker: Timer | null = null
export function showOffice(on?: Gdk.Monitor) {
  if (!officeWin) return
  closeAny()
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) officeWin.gdkmonitor = mon
  if (picked.peek() === null) setPicked(inbox.peek()[0]?.id ?? view.peek().roster[0]?.thread_id ?? null)
  // the keyboard while it is up, like the hub: it is a click-away sheet, not a place to type past
  officeWin.keymode = Astal.Keymode.EXCLUSIVE
  officeWin.visible = true
  reattach()
  armClickaway(() => hideOffice())
}
export function hideOffice() {
  if (officeWin) { officeWin.visible = false; officeWin.keymode = Astal.Keymode.NONE }
  endTerminal()
  disarmClickaway()
}
export function toggleOffice(on?: Gdk.Monitor) { if (officeWin?.visible) hideOffice(); else showOffice(on) }
/** open the office on thread `tid` — its workspace, picked (a click on a "waiting on you" toast) */
export function openOfficeAt(tid: number) {
  const t = agents.peek().threads.find((x) => x.id === tid)
  if (t?.workspace_id != null) setChosen(t.workspace_id)
  setPicked(tid)
  if (!officeWin?.visible) showOffice()
}
setOpener(openOfficeAt)

let talkEntry: Gtk.Entry | null = null
/** the office's people in walking order — the bench, then anyone on a thread who is not on it */
const people = view((a) => [...a.bench.map((c) => c.name), ...a.roster.map((r) => r.agent).filter((n) => !a.bench.some((c) => c.name === n))])
function stepPerson(d: 1 | -1) {
  const list = people.peek(), a = view.peek()
  if (!list.length) return
  const m = mode.peek()
  const cur = m.kind === "coworker" ? list.indexOf(a.bench.find((c) => c.agent_id === m.agentId)?.name ?? "") : -1
  const name = list[(cur + d + list.length) % list.length]
  const c = a.bench.find((x) => x.name === name)
  if (c) setMode({ kind: "coworker", agentId: c.agent_id })
  const r = a.roster.find((x) => x.agent === name)
  if (r) setPicked(r.thread_id)
}

export default function Office() {
  // CAPTURE, so the keys reach us before a focused button eats them; a focused entry keeps its
  // typing — only Esc gets through it
  const keys = new Gtk.EventControllerKey({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
  keys.connect("key-pressed", (_, kv) => {
    // the worker's terminal, focused, is theirs: every key goes to it, Esc too (Claude Code needs it)
    if (officeWin?.get_focus() instanceof Vte.Terminal) return false
    if (kv === Gdk.KEY_Escape) {
      // back out one step at a time: the open action, then the picked thread, then the office
      if (mode.peek().kind !== "none") setMode({ kind: "none" })
      else if (picked.peek() !== null) setPicked(null)
      else hideOffice()
      return true
    }
    if (officeWin?.get_focus() instanceof Gtk.Text) return false
    switch (kv) {
      case Gdk.KEY_j: case Gdk.KEY_Down: stepPerson(1); return true
      case Gdk.KEY_k: case Gdk.KEY_Up: stepPerson(-1); return true
      case Gdk.KEY_bracketleft: stepWs(-1); return true
      case Gdk.KEY_bracketright: stepWs(1); return true
      case Gdk.KEY_n: setMode({ kind: "new-ticket" }); return true
      case Gdk.KEY_h: setMode({ kind: "hire" }); return true
      case Gdk.KEY_Return: case Gdk.KEY_KP_Enter:
        if (mode.peek().kind === "coworker") { talkEntry?.grab_focus(); return true }
        return false
    }
    return false
  })
  // a fresh brief on every poll, so a reply's answer shows up while the rail is open
  agents.subscribe(() => { if (officeWin?.visible) loadBrief() })
  return (
    <window
      $={(self) => {
        officeWin = self
        self.add_controller(keys)
        // the animation runs only while someone can see it
        self.connect("notify::visible", () => {
          ticker?.cancel(); ticker = null
          if (self.visible) ticker = interval(100, () => { if (sim().step(view.peek())) setFrame((n) => n + 1) })
          peeker?.cancel(); peeker = null
          if (self.visible) peeker = interval(3000, () => { if (wide.peek()) loadThreadView() })
        })
      }}
      visible={false}
      cssClasses={["office"]}
      namespace="astal-shell-office"
      name="office"
      // like the hub: a sheet over the windows with a field beside it, so it stays up wherever
      // the pointer goes and the first click outside it closes it
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT}
      marginTop={36}
      marginLeft={48}
      application={app}
    >
      <box>
      <box
        cssClasses={["clickaway-field"]}
        hexpand
        vexpand
        $={(self) => {
          const g = new Gtk.GestureClick({ button: 0 })
          g.connect("pressed", () => hideOffice())
          self.add_controller(g)
        }}
      />
      <scrolledwindow cssClasses={["sheet", "right", "office-sheet"]} hexpand={false} halign={Gtk.Align.END} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}>
        <box orientation={Gtk.Orientation.VERTICAL}>
          <Panel title={"\u{f06a9}  OFFICE"} cssClasses={["card", "card-agents"]}>
            <Switcher />
            <Scene />
            <label cssClasses={["dim", "sm"]} label="j/k people · [ ] workspace · ⏎ talk · n ticket · h hire · esc back" xalign={0} />
          </Panel>
          {/* one fixed-size place under the room for whatever you are looking at — an action, the
              picked thread, or home (what waits on you) — so the rail never jumps */}
          <box orientation={Gtk.Orientation.VERTICAL} heightRequest={DETAIL_H} vexpand={false}>
            <ActionCard />
            <Panel title={pickedTitle} cssClasses={["card", "card-agents"]} vexpand visible={createComputed(() => mode().kind === "none" && picked() !== null && !wide())}>
              <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                  <Reply />
                  <Brief brief={brief} />
                </box>
              </scrolledwindow>
            </Panel>
            <Panel title={inbox((l) => (l.length ? `\u{f0e7e}  WAITING ON YOU · ${l.length}` : "\u{f0e7e}  HOME"))} cssClasses={["card", "card-agents"]} vexpand visible={createComputed(() => mode().kind === "none" && (picked() === null || wide()))}>
              <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                  <For each={inbox}>
                    {(t: Thread) => (
                      <button cssClasses={picked((p) => ["row", "thread-row", ...(p === t.id ? ["chip"] : [])])} onClicked={() => setPicked(t.id)}>
                        <box spacing={8}>
                          <label cssClasses={["dim", "sm"]} label={`#${t.id}`} widthChars={3} xalign={1} />
                          <label label={t.title} hexpand xalign={0} ellipsize={3} maxWidthChars={22} />
                          <label cssClasses={["pink", "sm"]} label={t.prompt?.summary ?? t.lead ?? ""} ellipsize={3} maxWidthChars={18} />
                        </box>
                      </button>
                    )}
                  </For>
                  <label cssClasses={["dim"]} wrap maxWidthChars={44} xalign={0}
                    label={inbox((l) => `${l.length ? "" : "Nothing waits on you. "}Click someone to talk to them, a desk or sticky to open it, yourself for the menu — and empty floor to come back here.`)} />
                </box>
              </scrolledwindow>
            </Panel>
          </box>
        </box>
      </scrolledwindow>
      <ThreadPane />
      </box>
    </window>
  )
}
