// The office: a rail on the right (the deck's agents cell toggles it, `astal-shell toggle office`)
// with one workspace at a glance (what waits on you, who is working, the board's counts), then the
// action card (hand a ticket to a coworker, file a ticket, hire) or the picked thread: a prompt's
// options as buttons, a reply line, its brief. ‹ › walks the workspaces.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import GLib from "gi://GLib?version=2.0"
import Pango from "gi://Pango?version=1.0"
import Vte from "gi://Vte?version=3.91"
import { execAsync } from "ags/process"
import { For, createComputed, createState, type Accessor } from "ags"
import { interval, type Timer } from "ags/time"
import { agents, dossier, threadView, post, ticketRoute, closeThread, fileTicket, startTicket, hire, coworkerSet, workspaceNew, aside, fire, ticketSet, ticketDelete, workspaceDelete, handOff, shiftSwitch, setOpener, type Agents, type Dossier, type Note, type Thread, type ThreadView } from "../lib/agents"
import { COLS, STATUS_ORDER, boardColumns, busiest, crewOf, statusGlyph, viewOf, type BoardItem, type Crew } from "../office/kit/crew"
import { ROLE } from "../lib/palette"
import { Panel } from "../lib/tui"
import { hhmm } from "../lib/format"
import { closeKeys } from "../lib/keys"
import { Brief } from "../panes/Agents"
import { armClickaway, closeAny, disarmClickaway, clickawayField } from "./Clickaway"

const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)

// which workspace's office is showing: the last one you had open, across restarts; until there is
// one (or it was deleted), Machine, else the one that needs you most
const LAST_WS = `${GLib.get_user_state_dir()}/astal-shell/office-workspace`
const [chosen, setChosen] = createState<number | null>((() => {
  try { const [ok, b] = GLib.file_get_contents(LAST_WS); const n = ok ? Number(new TextDecoder().decode(b).trim()) : NaN; return n > 0 ? n : null } catch { return null }
})())
function choose(id: number | null) {
  setChosen(id)
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(LAST_WS), 0o755)
    GLib.file_set_contents(LAST_WS, id === null ? "" : String(id))
  } catch (e) { console.error("office workspace:", String(e)) }
}
const wsId = createComputed(() => {
  const a = agents(), c = chosen()
  if (c !== null && (!a.ok || a.workspaces.some((w) => w.id === c))) return c
  return a.workspaces.find((w) => w.name.toLowerCase() === "machine")?.id ?? busiest(a)
})
/** the snapshot narrowed to one workspace — what the office draws and acts on */
const view = createComputed((): Agents => viewOf(agents(), wsId()))
const wsName = createComputed(() => agents().workspaces.find((w) => w.id === wsId())?.name ?? "—")
/** this workspace's shift, once its crews are split across shifts (Server.Shifts); else null */
const shiftOn = createComputed(() => {
  const a = agents(), ws = wsId()
  return (a.shifts ?? []).some((x) => x.workspace_id === ws && x.crew !== "all") ? a.workspaces.find((w) => w.id === ws)?.shift ?? "day" : null
})
const elsewhere = createComputed(() => { const a = agents(), ws = wsId(); return a.threads.filter((t) => t.workspace_id !== ws && needsYou(t)).length })
function stepWs(d: 1 | -1) {
  const list = agents.peek().workspaces
  if (!list.length) return
  const i = list.findIndex((w) => w.id === wsId.peek())
  choose(list[(i + d + list.length) % list.length].id)
  setMode({ kind: "none" })
}

const [picked, setPicked] = createState<number | null>(null)
const [brief, setBrief] = createState<Dossier | null>(null)
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
  | { kind: "crew" }
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

/** a click on someone: the one a ticket or a thread is being handed to, else their card and thread */
function clickPerson(c: Crew) {
  const m = mode.peek(), b = view.peek().bench.find((x) => x.name === c.name)
  if (m.kind === "ticket" && b) setMode({ kind: "confirm", id: m.id, agentId: b.agent_id, name: c.name })
  else if (m.kind === "handoff") setMode({ kind: "confirm-handoff", tid: m.tid, name: c.name })
  else {
    if (b) setMode({ kind: "coworker", agentId: b.agent_id })
    if (c.thread !== null) setPicked(c.thread)
  }
}
const toggle = (next: Mode) => setMode(JSON.stringify(mode.peek()) === JSON.stringify(next) ? { kind: "none" } : next)

/** the rail's fixed top: what waits on you, who is at work, the board's counts */
function Glance() {
  const crew = view((a) => crewOf(a))
  const board = view((a) => boardColumns(a))
  // handing work out needs everyone on the list; otherwise an idle coworker is only a count
  const shown = createComputed(() => {
    const everyone = ["ticket", "handoff"].includes(mode().kind)
    return crew().filter((c) => everyone || c.status === "working" || c.status === "waiting")
      .sort((x, y) => STATUS_ORDER.indexOf(x.status) - STATUS_ORDER.indexOf(y.status))
  })
  const working = crew((l) => l.filter((c) => c.status === "working").length)
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <label cssClasses={inbox((l) => (l.length ? ["pink"] : ["dim"]))} xalign={0} label={inbox((l) => (l.length ? `${l.length} waiting on you` : "nothing waits on you"))} />
      <box orientation={Gtk.Orientation.VERTICAL}>
        <For each={inbox}>
          {(t: Thread) => (
            <button cssClasses={picked((p) => ["row", "thread-row", ...(p === t.id ? ["chip"] : [])])} onClicked={() => { setMode({ kind: "none" }); setPicked(t.id) }}>
              <box orientation={Gtk.Orientation.VERTICAL}>
                <label label={`#${t.id} ${t.title}`} xalign={0} ellipsize={3} maxWidthChars={GLANCE_CHARS} />
                <label cssClasses={["pink", "sm"]} label={t.prompt?.summary ?? t.lead ?? ""} xalign={0} ellipsize={3} maxWidthChars={GLANCE_CHARS} />
              </box>
            </button>
          )}
        </For>
      </box>
      <button cssClasses={["row", "thread-row"]} tooltipText="the whole crew" onClicked={() => toggle({ kind: "crew" })}>
        <label cssClasses={["dim"]} xalign={0} label={createComputed(() => `crew · ${working()} working of ${crew().length}`)} />
      </button>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <For each={shown}>
          {(c: Crew) => (
            <button cssClasses={picked((p) => ["row", "thread-row", ...(p !== null && p === c.thread ? ["chip"] : [])])} onClicked={() => clickPerson(c)}>
              <box spacing={8}>
                <label cssClasses={[c.status === "working" ? "st-working" : c.status === "waiting" ? "pink" : "dim"]} label={statusGlyph(c.status)} />
                <label label={c.name} xalign={0} widthChars={9} />
                <label cssClasses={["dim", "sm"]} label={c.title} xalign={0} hexpand ellipsize={3} maxWidthChars={GLANCE_CHARS - 12} />
              </box>
            </button>
          )}
        </For>
      </box>
      <box homogeneous spacing={2}>
        {COLS.map((name, col) => (
          <button cssClasses={mode((m) => ["row", "thread-row", ...(m.kind === "column" && m.col === col ? ["chip"] : [])])} onClicked={() => toggle({ kind: "column", col })}>
            <box orientation={Gtk.Orientation.VERTICAL}>
              <label label={board((c) => String(c[col]?.items.length ?? 0))} />
              <label cssClasses={["dim", "sm"]} label={name.toLowerCase()} />
            </box>
          </button>
        ))}
      </box>
      <button cssClasses={["act"]} tooltipText="your desk: hire, new ticket, notes, the crew" onClicked={() => toggle({ kind: "boss" })}><label label="desk" /></button>
    </box>
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
      <button cssClasses={["act"]} visible={shiftOn((x) => x !== null)} tooltipText={shiftOn((x) => `the ${x} shift is on — click for the ${x === "night" ? "day" : "night"} shift`)}
        onClicked={() => { const ws = wsId.peek(), on = shiftOn.peek(); if (ws !== null && on) void shiftSwitch(ws, on === "night" ? "day" : "night") }}>
        <label label={shiftOn((x) => (x === "night" ? "☾ night" : "☼ day"))} />
      </button>
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

/** the card under the glance for whatever the last click started */
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
  const crew = view((a) => crewOf(a))
  /** the model someone runs on and its harness: their own setting, else their archetype's */
  const runsOn = (name: string) => {
    const a = view.peek(), b = a.bench.find((x) => x.name === name)
    const key = b?.model ? `${b.model.provider}/${b.model.model}` : a.archetypes.find((x) => x.name === b?.archetype)?.model
    return key ? choiceLabel(key) : ""
  }
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
      if (w) choose(w.id)
    }
  }
  const [settings, setSettings] = createState(false)
  const [more, setMore] = createState(false)
  // the last thing you said to whoever's card is open, and their answer (null while they think)
  const exchange = createComputed(() => { const c = coworker(); return c ? talks()[c.agent_id] ?? null : null })
  const talkTo = async (q: string) => {
    const c = coworker.peek(), ws = wsId.peek()
    if (!c || ws === null || !q.trim()) return
    setTalks({ ...talks.peek(), [c.agent_id]: { name: c.name, q: q.trim(), a: null } })
    const a = await aside(ws, c.agent_id, q.trim())
    setTalks({ ...talks.peek(), [c.agent_id]: { name: c.name, q: q.trim(), a: a || "(no answer)" } })
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
        case "crew": return `\u{f0004}  CREW · ${crew().length}`
        default: return `\u{f0e7e}  TICKET #${m.id}`
      }
    })} cssClasses={["card", "card-agents"]} vexpand visible={mode((m) => m.kind !== "none")}>
      <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
      {/* the crew: everyone on the bench, what they are, what runs them, what they are on */}
      <box orientation={Gtk.Orientation.VERTICAL} spacing={4} visible={is("crew")}>
        <For each={crew}>
          {(c: Crew) => (
            <button cssClasses={["row", "thread-row"]} onClicked={() => { const b = view.peek().bench.find((x) => x.name === c.name); if (b) setMode({ kind: "coworker", agentId: b.agent_id }); if (c.thread !== null) setPicked(c.thread) }}>
              <box orientation={Gtk.Orientation.VERTICAL} spacing={1}>
                <box spacing={8}>
                  <label cssClasses={[c.status === "working" ? "st-working" : c.status === "waiting" ? "pink" : "dim"]} label={c.status === "working" ? "●" : c.status === "waiting" ? "!" : "○"} widthChars={1} />
                  <label cssClasses={c.status === "idle" ? ["dim"] : []} label={c.name} xalign={0} widthChars={9} />
                  <label cssClasses={["dim", "sm"]} label={`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`} xalign={0} widthChars={16} />
                  <label cssClasses={["cyan", "sm"]} label={runsOn(c.name)} xalign={0} hexpand ellipsize={3} />
                </box>
                <label cssClasses={["dim", "sm"]} label={c.thread !== null ? `   #${c.thread} ${c.title}` : "   on the bench"} xalign={0} ellipsize={3} maxWidthChars={46} />
              </box>
            </button>
          )}
        </For>
      </box>
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
          <button cssClasses={["act"]} onClicked={() => setMode({ kind: "crew" })}><label label="crew" /></button>
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
      {/* a board column as a list */}
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
            if (ws !== null && (await workspaceDelete(ws))) { choose(null); cancel() }
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
// workers' view — and it ends itself when this client goes. One client; a thread in another
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
  const sock = `tlon-workspace-${ws}`
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

// the detail box under the glance: fixed, so the rail never jumps as cards come and go
const DETAIL_H = 380
const GLANCE_CHARS = 34
let officeWin: Astal.Window | null = null
let peeker: Timer | null = null
export function showOffice(on?: Gdk.Monitor) {
  if (!officeWin) return
  closeAny()
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) officeWin.gdkmonitor = mon
  if (picked.peek() === null) setPicked(inbox.peek()[0]?.id ?? null)
  // the keyboard while it is up, like the hub: it is a click-away sheet, not a place to type past
  officeWin.keymode = Astal.Keymode.EXCLUSIVE
  officeWin.visible = true
  reattach()
  armClickaway(() => hideOffice())
}
export const officeVisible = () => !!officeWin?.visible
export function hideOffice() {
  if (officeWin) { officeWin.visible = false; officeWin.keymode = Astal.Keymode.NONE }
  endTerminal()
  disarmClickaway()
}
export function toggleOffice(on?: Gdk.Monitor) { if (officeWin?.visible) hideOffice(); else showOffice(on) }
/** open the office on thread `tid` — its workspace, picked (a click on a "waiting on you" toast) */
export function openOfficeAt(tid: number) {
  const t = agents.peek().threads.find((x) => x.id === tid)
  if (t?.workspace_id != null) choose(t.workspace_id)
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
  const keys = closeKeys({
    close: hideOffice,
    capture: true,
    // the worker's terminal, focused, is theirs: every key goes to it, Esc too (Claude Code needs it)
    skip: () => officeWin?.get_focus() instanceof Vte.Terminal,
    // back out one step at a time: the open action, then the picked thread, then the office
    onEsc: () => {
      if (mode.peek().kind !== "none") setMode({ kind: "none" })
      else if (picked.peek() !== null) setPicked(null)
      else hideOffice()
    },
    onKey: (kv) => {
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
  } })
  // a fresh brief on every poll, so a reply's answer shows up while the rail is open
  agents.subscribe(() => { if (officeWin?.visible) loadBrief() })
  return (
    <window
      $={(self) => {
        officeWin = self
        self.add_controller(keys)
        self.connect("notify::visible", () => {
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
        $={(self) => clickawayField(self, hideOffice)}
      />
      <scrolledwindow cssClasses={["sheet", "right", "office-sheet"]} hexpand={false} halign={Gtk.Align.END} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}>
        <box orientation={Gtk.Orientation.VERTICAL}>
          <Panel title={"\u{f06a9}  OFFICE"} cssClasses={["card", "card-agents"]}>
            <Switcher />
            <Glance />
            <label cssClasses={["dim", "sm"]} label="j/k people · [ ] workspace · ⏎ talk · n ticket · h hire · esc back" xalign={0} wrap maxWidthChars={GLANCE_CHARS} />
          </Panel>
          {/* one fixed-size place under the glance for whatever you are looking at, so the rail never jumps */}
          <box orientation={Gtk.Orientation.VERTICAL} heightRequest={DETAIL_H} vexpand={false} visible={createComputed(() => mode().kind !== "none" || picked() !== null)}>
            <ActionCard />
            <Panel title={pickedTitle} cssClasses={["card", "card-agents"]} vexpand visible={createComputed(() => mode().kind === "none" && picked() !== null && !wide())}>
              <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
                <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
                  <Reply />
                  <Brief brief={brief} />
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
