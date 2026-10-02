// The office: a rail on the right (the deck's agents cell toggles it, `astal-shell toggle office`)
// with the Tlön roster as a pixel-art floor — you in the corner office with your inbox on the
// desk, the workspace leads on their own row, every other live session at a desk on the floor —
// then the inbox (threads waiting on you) and the picked thread: its brief, a prompt's options as
// buttons, and a reply line. Every colour is a ROLE from the live theme, so it follows a switch.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Cairo from "cairo"
import { For, createComputed, createState } from "ags"
import { interval, type Timer } from "ags/time"
import { agents, dossier, post, type Dossier, type Seat, type Thread } from "../lib/agents"
import { ROLE, type Role } from "../lib/palette"
import { theme } from "../lib/theme"
import { Panel } from "../lib/tui"
import { Brief } from "../panes/Agents"

// logical pixels: the scene is drawn on a W-wide grid and blown up S times, nearest-neighbour
const S = 3
const W = 144
const CELL_W = 44, LEAD_W = 56, BOSS_W = 60, CELL_H = 38

// sprites: one char per pixel, "." clear; the letters are looked up in the paint map at draw time
const BODY = [
  "....hhhh....",
  "..hhhhhhhh..",
  "..hhhhhhhh..",
  "..hffffffh..",
  "..fkffffkf..",
  "..ffffffff..",
  "...ffffff...",
  ".....ff.....",
  "..ssssssss..",
  ".ssssssssss.",
  "ssssssssssss",
  "ssssssssssss",
  "ssssssssssss",
  "ssssssssssss",
]
const ASLEEP = "..fkkffkkf.." // row 4, eyes shut
const TIE = [[5, 8], [6, 8], [5, 9], [6, 9], [5, 10], [6, 10], [5, 11], [6, 11]]
const BADGE = [[8, 9], [9, 9], [8, 10], [9, 10]]
const MONITOR = [
  "oooooooooo",
  "o........o",
  "o........o",
  "o........o",
  "o........o",
  "o........o",
  "oooooooooo",
  "....oo....",
  "...oooo...",
]
const BUBBLE = [
  ".aaaaa.",
  "aaakaaa",
  "aaakaaa",
  "aaakaaa",
  "aaaaaaa",
  "aaakaaa",
  ".aaaaa.",
  "...a...",
]
const ZED = ["zzzzz", "...z.", "..z..", ".z...", "zzzzz"]

type Desk = { x: number; y: number; w: number; kind: "boss" | "lead" | "worker"; seat?: Seat; thread?: Thread }
type Hit = { x: number; y: number; w: number; h: number; tid: number | null; tip: string }

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

const threadOf = (id: number) => agents.peek().threads.find((t) => t.id === id)
const needsYou = (t?: Thread) => !!t && (!!t.awaiting || !!t.prompt)
const inbox = agents((a) => a.threads.filter(needsYou))
const pickedThread = createComputed(() => { const id = picked(); return agents().threads.find((t) => t.id === id) ?? null })
// a staffed thread can be closed and so missing from `threads`; its roster row still names it
const pickedTitle = createComputed(() => {
  const id = picked(), a = agents()
  return id === null ? "" : `#${id}  ${a.threads.find((t) => t.id === id)?.title ?? a.roster.find((r) => r.thread_id === id)?.title ?? ""}`
})

/** Seat the roster: you, then a row of leads, then the floor three to a row. */
function layout(a: ReturnType<typeof agents.peek>): { desks: Desk[]; height: number } {
  const desks: Desk[] = [{ x: (W - BOSS_W) / 2, y: 8, w: BOSS_W, kind: "boss" }]
  const leads = a.roster.filter((r) => r.lead)
  const floor = a.roster.filter((r) => !r.lead)
  let y = 52
  if (leads.length) {
    leads.forEach((r, i) => {
      const per = Math.min(2, leads.length - Math.floor(i / 2) * 2)
      const gap = (W - per * LEAD_W) / (per + 1)
      desks.push({ x: Math.round(gap + (i % 2) * (LEAD_W + gap)), y: y + Math.floor(i / 2) * (CELL_H + 2), w: LEAD_W, kind: "lead", seat: r, thread: threadOf(r.thread_id) })
    })
    y += Math.ceil(leads.length / 2) * (CELL_H + 2) + 4
  }
  const floorTop = y
  floor.forEach((r, i) => {
    desks.push({ x: 4 + (i % 3) * (CELL_W + 2), y: floorTop + Math.floor(i / 3) * (CELL_H + 2), w: CELL_W, kind: "worker", seat: r, thread: threadOf(r.thread_id) })
  })
  const height = floorTop + Math.max(1, Math.ceil(floor.length / 3)) * (CELL_H + 2) + 2
  return { desks, height }
}

function Scene() {
  let area: Gtk.DrawingArea | null = null
  let hits: Hit[] = []
  const hitAt = (x: number, y: number) => hits.find((h) => x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h)

  const draw = (_: Gtk.DrawingArea, cr: Cairo.Context, w: number) => {
    const a = agents.peek()
    const f = frame.peek()
    const { desks, height } = layout(a)
    const ox = Math.floor((w - W * S) / 2)
    cr.setAntialias(Cairo.Antialias.NONE)
    const paint = (c: string) => { const x = c.replace("#", ""); cr.setSourceRGB(parseInt(x.slice(0, 2), 16) / 255, parseInt(x.slice(2, 4), 16) / 255, parseInt(x.slice(4, 6), 16) / 255) }
    const px = (x: number, y: number, pw: number, ph: number, c: string) => { paint(c); cr.rectangle(ox + x * S, y * S, pw * S, ph * S); cr.fill() }
    const blit = (rows: string[], x: number, y: number, map: Record<string, string>) =>
      rows.forEach((row, j) => { for (let i = 0; i < row.length; i++) { const c = map[row[i]]; if (c) px(x + i, y + j, 1, 1, c) } })

    // the floor: a faint checker; the corner office carpeted, walled off with a door
    for (let ty = 48; ty < height; ty += 8) for (let tx = 0; tx < W; tx += 8) px(tx, ty, 8, 8, ((tx + ty) / 8) % 2 ? ROLE.panel : ROLE.ground)
    px(0, 0, W, 6, ROLE.edge)
    px(0, 6, W, 1, ROLE.structure)
    px(0, 7, W, 41, ROLE.raised)
    px(0, 47, W, 1, ROLE.structure)
    px(W / 2 - 8, 47, 16, 1, ROLE.raised)
    if (a.roster.some((r) => r.lead)) {
      const rows = Math.ceil(a.roster.filter((r) => r.lead).length / 2)
      px(2, 50, W - 4, rows * (CELL_H + 2), ROLE.raised)
    }

    hits = []
    cr.selectFontFace("ComicShannsMono Nerd Font", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    cr.setFontSize(12)
    for (const d of desks) {
      const t = d.thread
      const warm = d.kind === "boss" || !!d.seat?.warm
      const asks = d.kind !== "boss" && needsYou(t)
      const shirt = d.kind === "boss" ? ROLE.attention : (ROLE[(d.seat?.archetype ?? "") as Role] ?? ROLE.body)
      const cx = d.x + Math.round(d.w / 2) - 2
      // the person, then the desk in front of them
      const body = warm || asks ? BODY : BODY.map((r, j) => (j === 4 ? ASLEEP : r))
      blit(body, cx, d.y + 7, { h: ROLE.inactive, f: ROLE.prose, k: ROLE.fieldInk, s: shirt })
      if (d.kind === "boss") for (const [i, j] of TIE) px(cx + i, d.y + 7 + j, 1, 1, ROLE.alarm)
      if (d.kind === "lead") for (const [i, j] of BADGE) px(cx + i, d.y + 7 + j, 1, 1, ROLE.body)
      // hands on the keys, alternating while warm
      const up = warm && d.kind !== "boss" && (f + d.x) % 2 === 0
      px(cx + 1, d.y + 18 - (up ? 1 : 0), 2, 1, ROLE.prose)
      px(cx + 9, d.y + 18 - (warm && !up && d.kind !== "boss" ? 1 : 0), 2, 1, ROLE.prose)
      // the monitor: code scrolling while warm, the ask blinking when it waits on you, dark asleep
      const mx = d.x + 3, my = d.y + 10
      blit(MONITOR, mx, my, { o: ROLE.inactive })
      if (asks) px(mx + 1, my + 1, 8, 5, f % 2 ? ROLE.attention : ROLE.raised)
      else if (warm) {
        px(mx + 1, my + 1, 8, 5, ROLE.ground)
        for (let l = 0; l < 3; l++) px(mx + 2, my + 1 + l * 2, 1 + ((f + l * 3 + (d.seat?.thread_id ?? 0)) % 6), 1, ROLE.live)
      } else { px(mx + 1, my + 1, 8, 5, ROLE.ground); px(mx + 8, my + 5, 1, 1, ROLE.inactive) }
      // the desk; your inbox on yours, one sheet per thread waiting on you
      px(d.x, d.y + 19, d.w, 2, ROLE.structure)
      px(d.x + 1, d.y + 21, d.w - 2, 10, ROLE.borderInactive)
      px(d.x + d.w - 12, d.y + 24, 8, 1, ROLE.structure)
      if (d.kind === "boss") for (let p = 0; p < Math.min(6, a.awaiting); p++) px(d.x + d.w - 14, d.y + 18 - p * 2, 8, 1, ROLE.prose)
      // over their head: the ask, or sleep
      if (asks) blit(BUBBLE, cx + 10, d.y - 1 + (f % 2), { a: ROLE.attention, k: ROLE.fieldInk })
      else if (!warm) blit(ZED, cx + 11, d.y + 2 - (f % 3), { z: ROLE.inactive })
      // the nameplate, at the screen's own resolution
      const name = d.kind === "boss" ? (a.awaiting ? `you - ${a.awaiting} waiting` : "you") : `${d.seat?.agent ?? ""} #${d.seat?.thread_id ?? ""}`
      paint(d.kind === "boss" ? ROLE.attention : asks ? ROLE.attention : warm ? shirt : ROLE.inactive)
      const tw = cr.textExtents(name).width
      cr.moveTo(ox + (d.x + d.w / 2) * S - tw / 2, (d.y + CELL_H) * S - 2)
      cr.showText(name)
      // the picked desk wears the cursor's corner brackets
      const tid = d.kind === "boss" ? (inbox.peek()[0]?.id ?? null) : (d.seat?.thread_id ?? null)
      const hx = ox + d.x * S - 2, hy = d.y * S, hw = d.w * S + 4, hh = (CELL_H + 1) * S
      hits.push({ x: hx, y: hy, w: hw, h: hh, tid, tip: d.kind === "boss" ? (a.awaiting ? `${a.awaiting} thread(s) waiting on you` : "nothing waits on you") : `${d.seat?.agent} · #${d.seat?.thread_id} ${d.seat?.title}${t?.prompt ? `\nasks: ${t.prompt.summary}` : t?.awaiting ? `\nawaits ${t.awaiting}` : ""}\n${warm ? "working" : "idle"}` })
      if (d.kind !== "boss" && tid !== null && tid === picked.peek()) {
        paint(ROLE.body); cr.setLineWidth(2); cr.setAntialias(Cairo.Antialias.NONE)
        const k = 10
        for (const [x0, y0, sx, sy] of [[hx, hy, 1, 1], [hx + hw, hy, -1, 1], [hx, hy + hh, 1, -1], [hx + hw, hy + hh, -1, -1]]) {
          cr.moveTo(x0 + sx * k, y0); cr.lineTo(x0, y0); cr.lineTo(x0, y0 + sy * k); cr.stroke()
        }
      }
    }
    if (!a.ok || a.roster.length === 0) {
      const msg = a.ok ? "nobody on the clock" : (a.note ?? "channel down")
      paint(a.ok ? ROLE.inactive : ROLE.alarm)
      const tw = cr.textExtents(msg).width
      cr.moveTo(ox + (W * S) / 2 - tw / 2, 64 * S); cr.showText(msg)
    }
    if (area && area.heightRequest !== height * S) area.heightRequest = height * S
  }

  const redraw = () => area?.queue_draw()
  agents.subscribe(redraw); frame.subscribe(redraw); picked.subscribe(redraw); theme.subscribe(redraw)
  return (
    <Gtk.DrawingArea
      widthRequest={W * S}
      heightRequest={200 * S}
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
          if (self.visible) ticker = interval(400, () => setFrame((n) => n + 1))
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
