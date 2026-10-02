// The office: a rail on the right (the deck's agents cell toggles it, `astal-shell toggle office`)
// with the Tlön roster as a pixel-art office (lib/office.ts), then the inbox (threads waiting on
// you) and the picked thread: a prompt's options as buttons, a reply line, its brief.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Cairo from "cairo"
import { For, createComputed, createState } from "ags"
import { interval, type Timer } from "ags/time"
import { agents, dossier, post, type Dossier, type Thread } from "../lib/agents"
import { OfficeSim, S, W, type Hit } from "../lib/office"
import { theme } from "../lib/theme"
import { Panel } from "../lib/tui"
import { Brief } from "../panes/Agents"

const sim = new OfficeSim()

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

const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)
const inbox = agents((a) => a.threads.filter(needsYou))
const pickedThread = createComputed(() => { const id = picked(); return agents().threads.find((t) => t.id === id) ?? null })
// a staffed thread can be closed and so missing from `threads`; its roster row still names it
const pickedTitle = createComputed(() => {
  const id = picked(), a = agents()
  return id === null ? "" : `#${id}  ${a.threads.find((t) => t.id === id)?.title ?? a.roster.find((r) => r.thread_id === id)?.title ?? ""}`
})

function Scene() {
  let area: Gtk.DrawingArea | null = null
  let hits: Hit[] = []
  const hitAt = (x: number, y: number) => hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)

  const draw = (_: Gtk.DrawingArea, cr: Cairo.Context, w: number) => {
    const out = sim.draw(cr, w, agents.peek(), picked.peek())
    hits = out.hits
    if (area && area.heightRequest !== out.height * S) area.heightRequest = out.height * S
  }

  const redraw = () => area?.queue_draw()
  agents.subscribe(redraw); frame.subscribe(redraw); picked.subscribe(redraw); theme.subscribe(redraw)
  return (
    <Gtk.DrawingArea
      widthRequest={W * S}
      heightRequest={240 * S}
      hasTooltip
      $={(self) => {
        area = self
        self.set_draw_func(draw)
        const click = new Gtk.GestureClick({ button: 1 })
        click.connect("pressed", (_, _n, x, y) => { const h = hitAt(x, y); if (h?.tid != null) setPicked(h.tid) })
        self.add_controller(click)
        const motion = new Gtk.EventControllerMotion()
        motion.connect("motion", (_, x, y) => self.set_cursor_from_name(hitAt(x, y)?.tid != null ? "pointer" : null))
        self.add_controller(motion)
        self.connect("query-tooltip", (_, x, y, _kb, tip) => { const h = hitAt(x, y); if (!h) return false; tip.set_text(h.tip); return true })
      }}
    />
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
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) officeWin.gdkmonitor = mon
  if (picked.peek() === null) setPicked(inbox.peek()[0]?.id ?? agents.peek().roster[0]?.thread_id ?? null)
  officeWin.visible = true
}
export function hideOffice() { if (officeWin) officeWin.visible = false }
export function toggleOffice(on?: Gdk.Monitor) { if (officeWin?.visible) hideOffice(); else showOffice(on) }

export default function Office() {
  const keys = new Gtk.EventControllerKey()
  keys.connect("key-pressed", (_, kv) => { if (kv === Gdk.KEY_Escape) { hideOffice(); return true } return false })
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
          if (self.visible) ticker = interval(100, () => { sim.step(agents.peek()); setFrame((n) => n + 1) })
        })
      }}
      visible={false}
      cssClasses={["office"]}
      namespace="astal-shell-office"
      name="office"
      keymode={Astal.Keymode.ON_DEMAND}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
    >
      <scrolledwindow cssClasses={["sheet", "right", "office-sheet"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}>
        <box orientation={Gtk.Orientation.VERTICAL}>
          <Panel title={"\u{f06a9}  OFFICE"} cssClasses={["card", "card-agents"]}><Scene /></Panel>
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
    </window>
  )
}
