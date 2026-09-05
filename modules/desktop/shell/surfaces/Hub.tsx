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
import { timeout, type Timer } from "ags/time"
import { subprocess, type Process } from "ags/process"
import { Panel, RuleH } from "../lib/tui"
import { NoticeCard } from "./Notifications"

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
  return (
    <box cssClasses={["toggles"]} spacing={6} homogeneous>
      <Toggle icon={"\u{f05a9}"} label="wifi" on={wifiOn} onToggle={() => { if (net.wifi) net.wifi.enabled = !net.wifi.enabled }} />
      <Toggle icon={"\u{f00af}"} label="bt" on={btOn} onToggle={() => bt.toggle()} />
      <Toggle icon={"\u{f009b}"} label="dnd" on={dnd} onToggle={() => (notifd.dontDisturb = !notifd.dontDisturb)} />
      <Toggle icon={"\u{f0cf3}"} label="awake" on={inhibit} onToggle={toggleInhibit} />
      <Toggle icon={"\u{f0e36}"} label={profile((p) => (p === "performance" ? "perf" : p === "power-saver" ? "saver" : "balanced"))} on={profile((p) => p === "performance")} onToggle={cycleProfile} />
    </box>
  )
}

let hubWin: Astal.Window | null = null
/** True while the hub is up — the toast window hides itself so the two never overlap. */
export const [hubOpen, setHubOpen] = createState(false)
export function showHub() {
  if (!hubWin) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) hubWin.gdkmonitor = mon
  hubWin.visible = true
}
export function toggleHub() {
  if (hubWin?.visible) hubWin.visible = false
  else showHub()
}

/** The 2px strip along the right edge: park the pointer there and the hub slides in. */
export function HotEdge() {
  let dwell: Timer | null = null
  const motion = new Gtk.EventControllerMotion()
  motion.connect("enter", () => { dwell?.cancel(); dwell = timeout(250, () => showHub()) })
  motion.connect("leave", () => { dwell?.cancel(); dwell = null })
  return (
    <window
      $={(self) => self.add_controller(motion)}
      visible
      cssClasses={["hotedge"]}
      namespace="astal-shell-hotedge"
      name="hotedge"
      layer={Astal.Layer.TOP}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
    >
      <box widthRequest={2} />
    </window>
  )
}

export default function Hub() {
  let leave: Timer | null = null
  const motion = new Gtk.EventControllerMotion()
  motion.connect("enter", () => { leave?.cancel(); leave = null })
  // a button press inside emits a synthetic leave (implicit grab), so the grace timer re-checks
  motion.connect("leave", () => {
    leave?.cancel()
    leave = timeout(600, () => { if (hubWin && !motion.containsPointer) hubWin.visible = false })
  })
  const keys = new Gtk.EventControllerKey()
  keys.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? ((hubWin!.visible = false), true) : false))
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
      layer={Astal.Layer.TOP}
      keymode={Astal.Keymode.ON_DEMAND}
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
