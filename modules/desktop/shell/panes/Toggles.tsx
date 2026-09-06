// The toggles: wifi, bt, dnd, awake, night, crt, zen, glass, next wallpaper, power profile.
// Lived in the hub; now the dashboard's (Andrew, 2026-09-05).
import Gtk from "gi://Gtk?version=4.0"
import Notifd from "gi://AstalNotifd"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import PowerProfiles from "gi://AstalPowerProfiles"
import { createBinding, createState } from "ags"
import { subprocess, type Process } from "ags/process"
import { night, toggleNight } from "../lib/night"
import { crt, cycleCrt } from "../lib/crt"
import { zen, setBackdrop, nextWallpaper, backdropMode } from "../surfaces/Backdrop"
import { glass, toggleGlass } from "../lib/glass"

const notifd = Notifd.get_default()

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

export function Toggles({ perRow = 4 }: { perRow?: number }) {
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
  const all = [
    <Toggle icon={"\u{f05a9}"} label="wifi" on={wifiOn} onToggle={() => { if (net.wifi) net.wifi.enabled = !net.wifi.enabled }} />,
    <Toggle icon={"\u{f00af}"} label="bt" on={btOn} onToggle={() => bt.toggle()} />,
    <Toggle icon={"\u{f009b}"} label="dnd" on={dnd} onToggle={() => (notifd.dontDisturb = !notifd.dontDisturb)} />,
    <Toggle icon={"\u{f0cf3}"} label="awake" on={inhibit} onToggle={toggleInhibit} />,
    <Toggle icon={"\u{f0594}"} label="night" on={night} onToggle={toggleNight} />,
    <Toggle icon={"\u{f0379}"} label={crt((m) => (m === "off" ? "crt" : m))} on={crt((m) => m !== "off")} onToggle={cycleCrt} />,
    <Toggle icon={"\u{f0e2a}"} label={backdropMode((m) => (m === "photo" ? "zen" : m))} on={zen} onToggle={() => setBackdrop("cycle")} />,
    <Toggle icon={"◐"} label="glass" on={glass} onToggle={toggleGlass} />,
    <Toggle icon={"\u{f0e58}"} label="next wp" on={createState(false)[0]} onToggle={nextWallpaper} />,
    <Toggle icon={"\u{f0e36}"} label={profile((p) => (p === "performance" ? "perf" : p === "power-saver" ? "saver" : "balanced"))} on={profile((p) => p === "performance")} onToggle={cycleProfile} />,
  ]
  const rows: JSX.Element[][] = []
  for (let i = 0; i < all.length; i += perRow) rows.push(all.slice(i, i + perRow))
  return (
    <box cssClasses={["toggles"]} orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      {rows.map((r) => <box spacing={6} homogeneous>{r}</box>)}
    </box>
  )
}

