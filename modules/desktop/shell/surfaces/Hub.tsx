// The right-hand hub: a column of cards beside the right edge — notification history grouped
// by app. Opens when the pointer parks on the right edge (a 2px hot
// strip), on Super+N, or `astal-shell toggle hub`; closes when the pointer leaves it, or Esc.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Notifd from "gi://AstalNotifd"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import PowerProfiles from "gi://AstalPowerProfiles"
import Hyprland from "gi://AstalHyprland"
import { createBinding, createComputed, createState } from "ags"
import { timeout, interval, type Timer } from "ags/time"
import { query } from "../lib/hyprsock"
import { subprocess, execAsync, type Process } from "ags/process"
import GLib from "gi://GLib?version=2.0"
import { Panel, RuleH } from "../lib/tui"
import { NoticeCard, groups } from "./Notifications"
import { VList } from "../lib/vlist"
import { isFullscreen } from "../lib/hypr"
import { night, toggleNight } from "../lib/night"
import { crt, cycleCrt } from "../lib/crt"
import { zen, setBackdrop } from "./Backdrop"
import { glass, toggleGlass } from "../lib/glass"
import { armClickaway, disarmClickaway } from "./Clickaway"

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
      <scrolledwindow cssClasses={["history"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} propagateNaturalHeight>
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
 * The hot edge: the pointer parked within 2px of a monitor's right edge for 400 ms opens the
 * hub on that monitor. Polled from Hyprland's socket at 5 Hz — a layer surface for the strip
 * would not shrink below 200px and swallowed clicks.
 */
export function startHotEdge() {
  let since = 0
  let armedFor: string | null = null
  let away = 0
  interval(200, () => {
    let x = 0, y = 0
    try { [x, y] = query("cursorpos").split(",").map((v) => Number(v.trim())) } catch { return }
    if (hubWin?.visible) {
      // open: close once the pointer has been off the hub's monitor-right column for a second
      since = 0
      const name = hubWin.gdkmonitor?.connector
      const m = Hyprland.get_default().get_monitors().find((mm) => mm.name === name)
      const inside = m ? x >= m.x + m.width - 440 && x < m.x + m.width && y >= m.y && y < m.y + m.height : true
      if (inside) away = 0
      else if (!away) away = Date.now()
      else if (Date.now() - away > 1000) { away = 0; hideHub() }
      return
    }
    away = 0
    const mon = Hyprland.get_default().get_monitors().find((m) => x >= m.x + m.width - 2 && x < m.x + m.width && y >= m.y && y < m.y + m.height)
    // no hot edge on a monitor showing a film
    if (!mon || isFullscreen(mon.name)) { since = 0; armedFor = null; return }
    if (armedFor !== mon.name) { armedFor = mon.name; since = Date.now(); return }
    if (Date.now() - since >= 400) {
      since = Date.now() + 1e9   // once per visit
      const g = app.get_monitors().find((m) => m.connector === mon.name)
      showHub(g)
    }
  })
}

export default function Hub() {
  let leave: Timer | null = null
  const motion = new Gtk.EventControllerMotion()
  motion.connect("enter", () => { leave?.cancel(); leave = null })
  // a button press inside emits a synthetic leave (implicit grab), so the grace timer re-checks
  motion.connect("leave", () => {
    leave?.cancel()
    leave = timeout(600, () => { if (hubWin && !motion.containsPointer) hideHub() })
  })
  const keys = new Gtk.EventControllerKey()
  keys.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? (hideHub(), true) : false))
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
      <box cssClasses={["sheet", "right"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={420} hexpand={false} halign={Gtk.Align.END} $={(self) => self.add_controller(motion)}>
        <Panel title={"\u{f009a}  NOTIFICATIONS"} cssClasses={["card", "card-notices"]}><History /></Panel>
      </box>
      </box>
    </window>
  )
}
