// The toggles: wifi, bt, dnd, awake, night, crt, zen, glass, next wallpaper, power profile.
// Lived in the hub; now the dashboard's (Andrew, 2026-09-05).
import { awake, toggleAwake } from "../lib/awake"
import Gtk from "gi://Gtk?version=4.0"
import Notifd from "gi://AstalNotifd"
import Network from "gi://AstalNetwork"
import Bluetooth from "gi://AstalBluetooth"
import PowerProfiles from "gi://AstalPowerProfiles"
import { createBinding, createState, type Accessor } from "ags"
import { night, toggleNight } from "../lib/night"
import { crt, cycleCrt } from "../lib/crt"
import { zen, setBackdrop, nextWallpaper, backdropMode } from "../surfaces/Backdrop"
import { theme, switching, setTheme } from "../lib/theme"
import { createComputed } from "ags"
import { glass, toggleGlass } from "../lib/glass"

const notifd = Notifd.get_default()

/** A toggle: icon + label, chip when on. */
function Toggle({ icon, label, on, onToggle }: { icon: string | Accessor<string>; label: any; on: any; onToggle: () => void }) {
  return (
    <button cssClasses={on((o: boolean) => ["toggle", ...(o ? ["chip"] : [])])} onClicked={onToggle}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
    </button>
  )
}

/** `only`: a subset by key (the hub pins wifi/bt/dnd/awake/night; the dashboard shows the lot). */
export function Toggles({ perRow = 4, only, omit = [] }: { perRow?: number; only?: string[]; omit?: string[] }) {
  const net = Network.get_default()
  const bt = Bluetooth.get_default()
  const pp = PowerProfiles.get_default()
  const wifiOn = createBinding(net, "wifi")((w) => !!w?.enabled)
  const btOn = createBinding(bt, "isPowered")
  const dnd = createBinding(notifd, "dontDisturb")
  // the idle inhibitor lives in lib/awake: on by default, remembered across restarts
  const inhibit = awake
  const toggleInhibit = toggleAwake
  const profile = createBinding(pp, "activeProfile")
  const cycleProfile = () => {
    const ps = pp.get_profiles().map((p) => p.profile)
    pp.set_active_profile(ps[(ps.indexOf(pp.activeProfile) + 1) % ps.length])
  }
  const entries = [
    { key: "wifi", el: (<Toggle icon={"\u{f05a9}"} label="wifi" on={wifiOn} onToggle={() => { if (net.wifi) net.wifi.enabled = !net.wifi.enabled }} />) },
    { key: "bt", el: (<Toggle icon={"\u{f00af}"} label="bt" on={btOn} onToggle={() => bt.toggle()} />) },
    { key: "dnd", el: (<Toggle icon={"\u{f009b}"} label="dnd" on={dnd} onToggle={() => (notifd.dontDisturb = !notifd.dontDisturb)} />) },
    { key: "awake", el: (<Toggle icon={"\u{f0176}"} label="awake" on={inhibit} onToggle={toggleInhibit} />) },
    { key: "night", el: (<Toggle icon={"\u{f0594}"} label="night" on={night} onToggle={toggleNight} />) },
    { key: "crt", el: (<Toggle icon={"\u{f0379}"} label={crt((m) => (m === "off" ? "crt" : m))} on={crt((m) => m !== "off")} onToggle={cycleCrt} />) },
    { key: "zen", el: (<Toggle icon={"\u{f0e2a}"} label={backdropMode((m) => (m === "photo" ? "zen" : m))} on={zen} onToggle={() => setBackdrop("cycle")} />) },
    // light/dark = zahir/aleph, live
    { key: "theme", el: (<Toggle icon={theme((t) => (t === "zahir" ? "\u{f0599}" : "\u{f0594}"))} label={createComputed(() => { const t = theme(), s = switching(); return (s ? "…" : t) })} on={theme((t) => t === "zahir")} onToggle={() => setTheme("toggle")} />) },
    { key: "glass", el: (<Toggle icon={"◐"} label="glass" on={glass} onToggle={toggleGlass} />) },
    { key: "next wp", el: (<Toggle icon={"\u{f0e58}"} label="next wp" on={createState(false)[0]} onToggle={nextWallpaper} />) },
    { key: "profile", el: (<Toggle icon={"\u{f0e36}"} label={profile((p) => (p === "performance" ? "perf" : p === "power-saver" ? "saver" : "balanced"))} on={profile((p) => p === "performance")} onToggle={cycleProfile} />) },
  ]
  const all = (only ? entries.filter((e) => only.includes(e.key)) : entries).filter((e) => !omit.includes(e.key)).map((e) => e.el)
  const rows: JSX.Element[][] = []
  for (let i = 0; i < all.length; i += perRow) rows.push(all.slice(i, i + perRow))
  return (
    <box cssClasses={["toggles"]} orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      {rows.map((r) => <box spacing={6} homogeneous>{r}</box>)}
    </box>
  )
}

