// The right-hand hub: a column of cards beside the right edge — notification history grouped
// by app, and toggles at the foot. Opens when the pointer parks on the right edge (a 2px hot
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
import { For, createBinding, createComputed, createState } from "ags"
import { timeout, interval, type Timer } from "ags/time"
import { query } from "../lib/hyprsock"
import { subprocess, execAsync, type Process } from "ags/process"
import GLib from "gi://GLib?version=2.0"
import { Panel, RuleH } from "../lib/tui"
import { NoticeCard } from "./Notifications"
import { night, toggleNight } from "../lib/night"
import { crt, cycleCrt } from "../lib/crt"
import { zen, setBackdrop } from "./Backdrop"
import { glass, toggleGlass } from "../lib/glass"
import { armClickaway, disarmClickaway } from "./Clickaway"

const notifd = Notifd.get_default()

function History() {
  const all = createBinding(notifd, "notifications")((ns) => [...ns].sort((a, b) => b.time - a.time))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={0}>
      <box spacing={8} cssClasses={["hub-head"]}>
        <label cssClasses={["k"]} label={all((ns) => `${ns.length} ${ns.length === 1 ? "notice" : "notices"}`)} hexpand xalign={0} />
        <button cssClasses={["act"]} onClicked={() => notifd.get_notifications().forEach((n) => n.dismiss())}><label label="clear all" /></button>
      </box>
      <For each={all}>{(n) => <NoticeCard n={n} />}</For>
      <label cssClasses={["dim"]} label="all quiet" visible={all((ns) => ns.length === 0)} xalign={0} />
    </box>
  )
}

/** A toggle: icon + label, chip when on. */
function Toggle({ icon, label, on, onToggle }: { icon: string; label: any; on: any; onToggle: () => void }) {
  return (
    <button cssClasses={on((o: boolean) => ["toggle", ...(o ? ["chip"] : [])])} onClicked={onToggle}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
    </button>
  )
}

function Toggles() {
  const net = Network.get_default()
  const bt = Bluetooth.get_default()
  const pp = PowerProfiles.get_default()
  const wifiOn = createBinding(net, "wifi")((w) => !!w?.enabled)
  const btOn = createBinding(bt, "isPowered")
  const dnd = createBinding(notifd, "dontDisturb")
  // idle inhibit: hold a systemd-inhibit while on; hypridle keeps running, this only blocks it
  const [inhibit, setInhibit] = createState(false)
  let proc: Process | null = null
  const toggleInhibit = () => {
    if (proc) { proc.kill(); proc = null; setInhibit(false) }
    else { proc = subprocess(["systemd-inhibit", "--what=idle", "--who=astal-shell", "--why=toggle", "sleep", "infinity"]); setInhibit(true) }
  }
  const profile = createBinding(pp, "activeProfile")
  const cycleProfile = () => {
    const ps = pp.get_profiles().map((p) => p.profile)
    pp.set_active_profile(ps[(ps.indexOf(pp.activeProfile) + 1) % ps.length])
  }
  // four per row; the hub stays the width of a notice
  const all = [
    <Toggle icon={"\u{f05a9}"} label="wifi" on={wifiOn} onToggle={() => { if (net.wifi) net.wifi.enabled = !net.wifi.enabled }} />,
    <Toggle icon={"\u{f00af}"} label="bt" on={btOn} onToggle={() => bt.toggle()} />,
    <Toggle icon={"\u{f009b}"} label="dnd" on={dnd} onToggle={() => (notifd.dontDisturb = !notifd.dontDisturb)} />,
    <Toggle icon={"\u{f0cf3}"} label="awake" on={inhibit} onToggle={toggleInhibit} />,
    <Toggle icon={"\u{f0594}"} label="night" on={night} onToggle={toggleNight} />,
    <Toggle icon={"\u{f0379}"} label={crt((m) => (m === "off" ? "crt" : m))} on={crt((m) => m !== "off")} onToggle={cycleCrt} />,
    <Toggle icon={"\u{f0e2a}"} label="zen" on={zen} onToggle={() => setBackdrop("toggle")} />,
    <Toggle icon={"◐"} label="glass" on={glass} onToggle={toggleGlass} />,
    <Toggle icon={"\u{f0e58}"} label="next wp" on={createState(false)[0]} onToggle={() => execAsync([`${GLib.get_home_dir()}/.local/bin/rotate-wallpaper`]).catch(console.error)} />,
    <Toggle icon={"\u{f0e36}"} label={profile((p) => (p === "performance" ? "perf" : p === "power-saver" ? "saver" : "balanced"))} on={profile((p) => p === "performance")} onToggle={cycleProfile} />,
  ]
  const rows: JSX.Element[][] = []
  for (let i = 0; i < all.length; i += 4) rows.push(all.slice(i, i + 4))
  return (
    <box cssClasses={["toggles"]} orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      {rows.map((r) => <box spacing={6} homogeneous>{r}</box>)}
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
    if (!mon) { since = 0; armedFor = null; return }
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
        self.add_controller(motion)
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
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      marginTop={36}
      application={app}
    >
      <box cssClasses={["sheet", "right"]} orientation={Gtk.Orientation.VERTICAL} widthRequest={420}>
        <Panel title={"\u{f009a}  NOTIFICATIONS"} cssClasses={["card", "card-notices"]}><History /></Panel>
        <box vexpand />
        <Panel title={"\u{f0493}  TOGGLES"} cssClasses={["card", "card-toggles"]}><Toggles /></Panel>
      </box>
    </window>
  )
}
