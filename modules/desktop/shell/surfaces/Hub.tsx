// The right-hand hub: a column of cards beside the right edge — notification history grouped
// by app. Opens when the pointer parks on the right edge (a 2px hot
// strip), on Super+N, or `astal-shell toggle hub`; closes on Esc / q or a click outside.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Notifd from "gi://AstalNotifd"
import Hyprland from "gi://AstalHyprland"
import { createState } from "ags"
import { interval } from "ags/time"
import { query } from "../lib/hyprsock"
import { Panel } from "../lib/tui"
import { NoticeCard, groups } from "./Notifications"
import { VList } from "../lib/vlist"
import { Toggles } from "../panes/Toggles"
import { isFullscreen } from "../lib/hypr"
import { deckVisible } from "./Deck"
import { officeVisible } from "./Office"
import { armClickaway, disarmClickaway } from "./Clickaway"
import { setting } from "../lib/settings"
import { closeKeys } from "../lib/keys"

const notifd = Notifd.get_default()

// The history is a virtualised list (lib/vlist): only the cards on screen exist as widgets,
// however long the backlog — ags's For built one per notice and detached/reattached them all
// on every change, which was the lag at a few thousand.
function History() {
  const head = groups((gs) => {
    const n = gs.reduce((a, g) => a + g.count, 0)
    return `${n} ${n === 1 ? "notice" : "notices"}${gs.length < n ? ` · ${gs.length} distinct` : ""}`
  })
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={0}>
      <box spacing={8} cssClasses={["hub-head"]}>
        <label cssClasses={["k"]} label={head} hexpand xalign={0} />
        <button cssClasses={["act"]} onClicked={() => notifd.get_notifications().forEach((n) => n.dismiss())}><label label="clear all" /></button>
      </box>
      <scrolledwindow cssClasses={["history"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} overlayScrolling={false} propagateNaturalHeight>
        <VList
          items={groups}
          id={(g) => g.key}
          equal={(a, b) => a.count === b.count && a.head.id === b.head.id}
          render={(g) => (<NoticeCard g={g} />) as Gtk.Widget}
        />
      </scrolledwindow>
      <label cssClasses={["dim"]} label="all quiet" visible={groups((gs) => gs.length === 0)} xalign={0} />
    </box>
  )
}

let hubWin: Astal.Window | null = null
/** True while the hub is up — the toast window hides itself so the two never overlap. */
export const [hubOpen, setHubOpen] = createState(false)
export function showHub(on?: Gdk.Monitor) {
  if (!hubWin) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) hubWin.gdkmonitor = mon
  hubWin.keymode = Astal.Keymode.EXCLUSIVE
  hubWin.visible = true
  armClickaway(() => hideHub())
}
export function hideHub() {
  if (hubWin) { hubWin.visible = false; hubWin.keymode = Astal.Keymode.NONE }
  disarmClickaway()
}
export function toggleHub() {
  if (hubWin?.visible) hideHub()
  else showHub()
}

/**
 * The hot edge: the pointer parked within 2px of a monitor's right edge for feel.hotEdgeMs opens the
 * hub on that monitor. Polled from Hyprland's socket at 5 Hz — a layer surface for the strip
 * would not shrink below 200px and swallowed clicks.
 *
 * The BARS are excluded: the bar's own right end holds the gauges, battery and agents, whose
 * popovers you reach by parking the pointer there — exactly the gesture that armed the edge.
 * The edge is the MAIN area between them.
 */
// $bar-height in style/_tokens.scss — the top bar and the deck's bottom row are both one bar tall.
const BAR_H = 36

export function startHotEdge() {
  let since = 0
  let armedFor: string | null = null
  interval(200, () => {
    let x = 0, y = 0
    try { [x, y] = query("cursorpos").split(",").map((v) => Number(v.trim())) } catch { return }
    // open: nothing here — the hub and the deck close on Esc or a click outside, not on the
    // pointer leaving (Andrew, 2026-09-07). The office rail lies along this same edge, so the
    // edge is quiet while it is open too
    if (hubWin?.visible || deckVisible() || officeVisible()) { since = 0; return }
    // the right edge only: the deck opens on a click (Andrew, 2026-09-07: no hover for it)
    const mons = Hyprland.get_default().get_monitors()
    const mon = mons.find(
      (m) => x >= m.x + m.width - 2 && x < m.x + m.width && y >= m.y + BAR_H && y < m.y + m.height - BAR_H,
    )
    // no hot edge on a monitor showing a film
    if (!mon || isFullscreen(mon.name)) { since = 0; armedFor = null; return }
    if (armedFor !== mon.name) { armedFor = mon.name; since = Date.now(); return }
    if (Date.now() - since >= setting("feel.hotEdgeMs").peek()) {
      since = Date.now() + 1e9   // once per visit
      showHub(app.get_monitors().find((m) => m.connector === mon.name))
    }
  })
}

export default function Hub() {
  const keys = closeKeys({ close: hideHub, q: true })
  return (
    <window
      $={(self) => {
        hubWin = self
        self.add_controller(keys)
        self.connect("notify::visible", () => setHubOpen(self.visible))
      }}
      visible={false}
      cssClasses={["hub"]}
      namespace="astal-shell-hub"
      name="hub"
      layer={Astal.Layer.OVERLAY} // above the clickaway, which sits on TOP
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
          g.connect("pressed", () => hideHub())
          self.add_controller(g)
        }}
      />
      <box cssClasses={["sheet", "right"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={420} hexpand={false} halign={Gtk.Align.END}>
        <Panel title={"\u{f009a}  NOTIFICATIONS"} cssClasses={["card", "card-notices"]}><History /></Panel>
        <box vexpand />
        {/* the quick five, pinned to the bottom; the full set is the dashboard's */}
        <Panel title={"\u{f0493}  TOGGLES"} cssClasses={["card", "card-toggles"]}><Toggles perRow={5} only={["wifi", "bt", "dnd", "awake", "night"]} /></Panel>
      </box>
      </box>
    </window>
  )
}
