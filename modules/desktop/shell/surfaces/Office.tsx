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
import { For, createComputed, createState, type Accessor } from "ags"
import { interval, type Timer } from "ags/time"
import { agents, dossier, post, fileTicket, startTicket, hire, coworkerSet, workspaceNew, aside, type Agents, type Dossier, type Thread } from "../lib/agents"
import { OfficeSim, S, W, type Hit } from "../lib/office"
import { theme } from "../lib/theme"
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
  return {
    ...a, threads, roster: a.roster.filter((r) => r.workspace_id === ws), bench: a.bench.filter((c) => c.workspace_id === ws),
    tickets: a.tickets.filter((t) => t.workspace_id === ws), projects: a.projects.filter((p) => p.workspace_id === ws),
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
let loading = 0
async function loadBrief() {
  const id = picked.peek()
  const my = ++loading
  const d = id === null ? null : await dossier(id)
  if (my === loading) setBrief(d)
}
picked.subscribe(loadBrief)

type Mode =
  | { kind: "none" }
  | { kind: "ticket"; id: number }
  | { kind: "confirm"; id: number; agentId: number; name: string }
  | { kind: "new-ticket" }
  | { kind: "hire" }
  | { kind: "coworker"; agentId: number }
  | { kind: "new-workspace" }
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
  return id === null ? "" : `#${id}  ${a.threads.find((t) => t.id === id)?.title ?? a.roster.find((r) => r.thread_id === id)?.title ?? ""}`
})

function act(h: Hit) {
  const m = mode.peek(), x = h.act
  if (x.kind === "pen") setMode({ kind: "new-ticket" })
  else if (x.kind === "hire") setMode({ kind: "hire" })
  else if (x.kind === "ticket") setMode(m.kind === "ticket" && m.id === x.id ? { kind: "none" } : { kind: "ticket", id: x.id })
  else if (x.kind === "person" && m.kind === "ticket" && x.agentId !== null) setMode({ kind: "confirm", id: m.id, agentId: x.agentId, name: x.name })
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
    const out = sim().draw(cr, w, view.peek(), picked.peek(), armed.peek())
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
        click.connect("pressed", (_, _n, x, y) => { const h = hitAt(x, y); if (h) act(h) })
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
      <label cssClasses={["amber"]} label={wsName} hexpand />
      <label cssClasses={["pink", "sm"]} label={elsewhere((n) => `! ${n} elsewhere`)} visible={elsewhere((n) => n > 0)} />
      <button cssClasses={["act"]} onClicked={() => stepWs(1)} tooltipText="next workspace"><label label="›" /></button>
      <button cssClasses={["act"]} onClicked={() => setMode({ kind: "new-workspace" })} tooltipText="new workspace"><label label="+" /></button>
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
  return [a.name, lead && "lead", a.read_only && "read-only (cannot write)", a.meta && "meta (oversees, never works a thread)", `default ${choiceLabel(a.model)}`].filter(Boolean).join(" · ")
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
  // the knobs open on what is set now: a coworker's policy, or nothing (the archetype's) for a hire
  mode.subscribe(() => {
    const c = coworker.peek()
    setModel(c?.model ? `${c.model.provider}/${c.model.model}` : null)
    setEffort(c?.model?.thinking ?? null)
    setAsk(c?.ask ?? null)
  })
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
      return m.kind === "new-ticket" ? "\u{f0e7e}  NEW TICKET" : m.kind === "hire" ? "\u{f0004}  HIRE" : m.kind === "new-workspace" ? "\u{f0004}  NEW WORKSPACE"
        : m.kind === "coworker" ? `\u{f0004}  ${coworker()?.name ?? ""}` : m.kind === "none" ? "" : `\u{f0e7e}  TICKET #${m.id}`
    })} cssClasses={["card", "card-agents"]} visible={mode((m) => m.kind !== "none")}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={6} visible={is("coworker")}>
        <entry cssClasses={["deck-entry"]} placeholderText={coworker((c) => `say something to ${c?.name ?? ""}…`)} $={(self) => { self.connect("activate", () => { talkTo(self.text); self.text = "" }) }} />
        <box spacing={6} visible={exchange((x) => !!x)}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={3} hexpand>
            <label cssClasses={["dim"]} label={exchange((x) => (x ? `you: ${x.q}` : ""))} xalign={0} wrap maxWidthChars={42} />
            <label cssClasses={exchange((x) => (x?.a === null ? ["dim"] : ["amber"]))} label={exchange((x) => (x ? `${x.name}: ${x.a ?? "thinking…"}` : ""))} xalign={0} wrap maxWidthChars={42} selectable />
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
          </box>
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
        <label label={armedTitle} xalign={0} wrap maxWidthChars={40} />
        <label cssClasses={["dim", "sm"]} label="click a coworker in the office to hand it over" xalign={0} />
        <box spacing={6}>
          <button cssClasses={["act"]} onClicked={() => start(null)}><label label="start with the lead" /></button>
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
    </Panel>
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
    </box>
  )
}

let officeWin: Astal.Window | null = null
let ticker: Timer | null = null
export function showOffice(on?: Gdk.Monitor) {
  if (!officeWin) return
  closeAny()
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) officeWin.gdkmonitor = mon
  if (picked.peek() === null) setPicked(inbox.peek()[0]?.id ?? view.peek().roster[0]?.thread_id ?? null)
  officeWin.visible = true
  armClickaway(() => hideOffice())
}
export function hideOffice() {
  if (officeWin) officeWin.visible = false
  disarmClickaway()
}
export function toggleOffice(on?: Gdk.Monitor) { if (officeWin?.visible) hideOffice(); else showOffice(on) }

export default function Office() {
  const keys = new Gtk.EventControllerKey()
  // Esc backs out of a half-done action first, then closes the rail
  keys.connect("key-pressed", (_, kv) => {
    if (kv !== Gdk.KEY_Escape) return false
    if (mode.peek().kind !== "none") setMode({ kind: "none" })
    else hideOffice()
    return true
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
          if (self.visible) ticker = interval(100, () => { sim().step(view.peek()); setFrame((n) => n + 1) })
        })
      }}
      visible={false}
      cssClasses={["office"]}
      namespace="astal-shell-office"
      name="office"
      // like the hub: a sheet over the windows with a field beside it, so it stays up wherever
      // the pointer goes and the first click outside it closes it
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.ON_DEMAND}
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
          </Panel>
          <ActionCard />
          <Panel title={inbox((l) => `\u{f0e7e}  INBOX · ${l.length}`)} cssClasses={["card", "card-agents"]} visible={inbox((l) => l.length > 0)}>
            <For each={inbox}>
              {(t: Thread) => (
                <button cssClasses={picked((p) => ["row", "thread-row", ...(p === t.id ? ["chip"] : [])])} onClicked={() => setPicked(t.id)}>
                  <box spacing={8}>
                    <label cssClasses={["dim", "sm"]} label={`#${t.id}`} widthChars={3} xalign={1} />
                    <label label={t.title} hexpand xalign={0} ellipsize={3} maxWidthChars={22} />
                    <label cssClasses={["pink", "sm"]} label={t.prompt?.summary ?? t.awaiting ?? ""} ellipsize={3} maxWidthChars={18} />
                  </box>
                </button>
              )}
            </For>
          </Panel>
          <Panel title={pickedTitle} cssClasses={["card", "card-agents"]} visible={picked((p) => p !== null)}>
            <Reply />
            <Brief brief={brief} />
          </Panel>
        </box>
      </scrolledwindow>
      </box>
    </window>
  )
}
